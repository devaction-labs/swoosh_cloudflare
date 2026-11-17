defmodule SwooshCloudflare.DeliverManyTest do
  use ExUnit.Case, async: true

  alias Swoosh.Adapters.Cloudflare

  @path "/accounts/acc/email/sending/send"

  setup do
    bypass = Bypass.open()
    config = [api_token: "t", account_id: "acc", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  defp emails(n) do
    for i <- 1..n do
      %Swoosh.Email{
        to: ["u#{i}@example.com"],
        from: "sender@example.com",
        subject: "Hi #{i}",
        html_body: "<p>Hi</p>"
      }
    end
  end

  # Echoes the first recipient as the message id, with a varying delay so
  # completion order differs from input order.
  defp echo_handler do
    fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      [to] = Jason.decode!(raw)["to"]
      Process.sleep(if String.starts_with?(to, "u1@"), do: 80, else: 5)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{"success" => true, "result" => %{"message_id" => to}})
      )
    end
  end

  test "keeps input order and honors max_concurrency: 1", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, "POST", @path, echo_handler())

    assert {:ok, results} =
             Cloudflare.deliver_many(emails(5), Keyword.put(config, :max_concurrency, 1))

    assert Enum.map(results, fn {:ok, %{id: id}} -> id end) ==
             Enum.map(1..5, &"u#{&1}@example.com")
  end

  test "keeps input order with higher concurrency", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, "POST", @path, echo_handler())

    assert {:ok, results} =
             Cloudflare.deliver_many(emails(5), Keyword.put(config, :max_concurrency, 3))

    assert Enum.map(results, fn {:ok, %{id: id}} -> id end) ==
             Enum.map(1..5, &"u#{&1}@example.com")
  end

  test "max_concurrency limits parallel requests", %{bypass: bypass, config: config} do
    in_flight = :counters.new(1, [])
    peak = :counters.new(1, [])

    Bypass.expect(bypass, "POST", @path, fn conn ->
      :counters.add(in_flight, 1, 1)

      if :counters.get(in_flight, 1) > :counters.get(peak, 1),
        do: :counters.put(peak, 1, :counters.get(in_flight, 1))

      Process.sleep(30)
      :counters.sub(in_flight, 1, 1)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"success" => true, "result" => %{}}))
    end)

    assert {:ok, results} =
             Cloudflare.deliver_many(emails(6), Keyword.put(config, :max_concurrency, 1))

    assert length(results) == 6
    assert :counters.get(peak, 1) == 1
  end

  test "receive_timeout: :infinity does not raise", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, "POST", @path, echo_handler())
    config = Keyword.put(config, :req_options, receive_timeout: :infinity)

    assert {:ok, [{:ok, %{id: "u1@example.com"}}, {:ok, %{id: "u2@example.com"}}]} =
             Cloudflare.deliver_many(emails(2), config)
  end
end
