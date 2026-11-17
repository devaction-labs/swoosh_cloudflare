defmodule SwooshCloudflare.QueuesTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Event
  alias SwooshCloudflare.Queues

  @base "/accounts/acc/queues/q1/messages"
  @fixtures Path.expand("../fixtures/events", __DIR__)

  setup do
    bypass = Bypass.open()
    config = [api_token: "tok", account_id: "acc", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  defp reply(conn, result) do
    body = %{"success" => true, "errors" => [], "messages" => [], "result" => result}

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  def handle(_event, _measurements, meta, parent), do: send(parent, {:meta, meta})

  defp json_body(conn) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(raw), conn}
  end

  defp message(body, content_type, extra \\ %{}) do
    Map.merge(
      %{
        "id" => "m1",
        "lease_id" => "lease-1",
        "attempts" => 1,
        "timestamp_ms" => 1_689_615_013_586,
        "body" => body,
        "metadata" => %{"CF-Content-Type" => content_type}
      },
      extra
    )
  end

  defp pull_one(bypass, config, msg) do
    Bypass.expect_once(bypass, "POST", @base <> "/pull", fn conn ->
      reply(conn, %{"message_backlog_count" => 1, "messages" => [msg]})
    end)

    assert {:ok, [result]} = Queues.pull("q1", config)
    result
  end

  describe "pull/3" do
    test "sends batch_size and visibility_timeout_ms and returns messages", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", @base <> "/pull", fn conn ->
        {body, conn} = json_body(conn)
        assert body == %{"batch_size" => 10, "visibility_timeout_ms" => 60_000}
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]

        reply(conn, %{"messages" => [message("hello", "text"), message("x", "text")]})
      end)

      assert {:ok, [%{id: "m1", lease_id: "lease-1", attempts: 1} = msg, _]} =
               Queues.pull("q1", config, batch_size: 10, visibility_timeout_ms: 60_000)

      assert msg.timestamp_ms == 1_689_615_013_586
      assert msg.body == "hello"
      assert msg.event == nil
    end

    test "sends an empty object by default and returns [] when empty", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", @base <> "/pull", fn conn ->
        {body, conn} = json_body(conn)
        assert body == %{}
        reply(conn, %{"message_backlog_count" => 0, "messages" => []})
      end)

      assert {:ok, []} = Queues.pull("q1", config)
    end

    test "decodes a plain JSON event body into body and event", %{bypass: bypass, config: config} do
      json = File.read!(Path.join(@fixtures, "bounced.json"))
      msg = pull_one(bypass, config, message(json, "json"))

      assert %{"type" => "cf.email.sending.message.bounced"} = msg.body
      assert %Event{type: :bounced, recipient: "user@example.net"} = msg.event
    end

    test "decodes a base64-wrapped JSON event body", %{bypass: bypass, config: config} do
      json = File.read!(Path.join(@fixtures, "delivered.json"))
      msg = pull_one(bypass, config, message(Base.encode64(json), "json"))

      assert %Event{type: :delivered} = msg.event
    end

    test "decodes JSON with no content type metadata", %{bypass: bypass, config: config} do
      msg = pull_one(bypass, config, Map.delete(message(~s({"a":1}), "json"), "metadata"))

      assert msg.body == %{"a" => 1}
      assert msg.event == nil
    end

    test "bytes bodies are base64-decoded, text bodies are left alone", %{
      bypass: bypass,
      config: config
    } do
      msg = pull_one(bypass, config, message(Base.encode64(<<1, 2, 3>>), "bytes"))
      assert msg.body == <<1, 2, 3>>
    end

    test "text bodies that look like JSON are not decoded", %{bypass: bypass, config: config} do
      msg = pull_one(bypass, config, message(~s({"a":1}), "text"))
      assert msg.body == ~s({"a":1})
    end

    test "undecodable json bodies are returned as is", %{bypass: bypass, config: config} do
      msg = pull_one(bypass, config, message("hello", "json"))
      assert msg.body == "hello"
      assert msg.event == nil
    end

    test "maps API errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", @base <> "/pull", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, Jason.encode!(%{"success" => false, "errors" => []}))
      end)

      assert {:error, {403, _reason, _body}} = Queues.pull("q1", config)
    end

    test "requires account_id", %{config: config} do
      assert_raise ArgumentError, ~r/:account_id/, fn ->
        Queues.pull("q1", Keyword.delete(config, :account_id))
      end
    end

    test "emits telemetry with the path and no token or payload", %{
      bypass: bypass,
      config: config
    } do
      id = {__MODULE__, make_ref()}
      parent = self()

      :telemetry.attach(id, [:swoosh_cloudflare, :request, :stop], &__MODULE__.handle/4, parent)

      on_exit(fn -> :telemetry.detach(id) end)

      Bypass.expect_once(bypass, "POST", @base <> "/pull", fn conn ->
        reply(conn, %{"messages" => []})
      end)

      assert {:ok, []} = Queues.pull("q1", config)
      assert_receive {:meta, %{path: @base <> "/pull", method: :post, status: 200} = meta}
      refute inspect(meta) =~ "tok"
    end
  end

  describe "ack/4" do
    test "acks lease ids and returns counts", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", @base <> "/ack", fn conn ->
        {body, conn} = json_body(conn)

        assert body == %{
                 "acks" => [%{"lease_id" => "l1"}, %{"lease_id" => "l2"}],
                 "retries" => []
               }

        reply(conn, %{"ackCount" => 2, "retryCount" => 0, "warnings" => []})
      end)

      assert {:ok, %{ack_count: 2, retry_count: 0}} = Queues.ack("q1", ["l1", "l2"], config)
    end

    test "supports retries with and without delay", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", @base <> "/ack", fn conn ->
        {body, conn} = json_body(conn)

        assert body == %{
                 "acks" => [%{"lease_id" => "l1"}],
                 "retries" => [
                   %{"lease_id" => "l2", "delay_seconds" => 600},
                   %{"lease_id" => "l3"}
                 ]
               }

        reply(conn, %{"ackCount" => 1, "retryCount" => 2, "warnings" => %{"w" => "x"}})
      end)

      assert {:ok, %{ack_count: 1, retry_count: 2, warnings: %{"w" => "x"}}} =
               Queues.ack("q1", ["l1"], config, retries: [{"l2", 600}, "l3"])
    end

    test "tolerates a missing result", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", @base <> "/ack", fn conn -> reply(conn, nil) end)

      assert {:ok, %{ack_count: 0, retry_count: 0, warnings: %{}}} =
               Queues.ack("q1", [], config)
    end

    test "maps rate limits", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", @base <> "/ack", fn conn ->
        conn |> Plug.Conn.put_resp_header("retry-after", "3") |> Plug.Conn.send_resp(429, "")
      end)

      assert {:error, {429, :rate_limited, 3}} = Queues.ack("q1", ["l1"], config)
    end
  end
end
