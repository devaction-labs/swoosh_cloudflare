defmodule SwooshCloudflare.ReqOptionsTest do
  use ExUnit.Case, async: true

  alias Swoosh.Adapters.Cloudflare

  @path "/accounts/acc/email/sending/send"

  defp email do
    %Swoosh.Email{
      to: [{"Alice", "alice@example.com"}],
      from: {"Sender", "sender@example.com"},
      subject: "Hi",
      html_body: "<p>Hi</p>"
    }
  end

  defp ok_resp(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(%{"success" => true, "result" => %{}}))
  end

  setup do
    bypass = Bypass.open()
    config = [api_token: "tok", account_id: "acc", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  test "extra headers reach the server and Authorization is kept", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-trace") == ["abc"]
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
      ok_resp(conn)
    end)

    config =
      Keyword.put(config, :req_options, headers: [{"x-trace", "abc"}, {"Authorization", "evil"}])

    assert {:ok, _} = Cloudflare.deliver(email(), config)
  end

  test "auth in req_options cannot override the Authorization header", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
      ok_resp(conn)
    end)

    config = Keyword.put(config, :req_options, auth: {:bearer, "other"})

    assert {:ok, _} = Cloudflare.deliver(email(), config)
  end

  test "receive_timeout from req_options overrides the default" do
    # A server that accepts connections and never answers.
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    on_exit(fn -> :gen_tcp.close(listen) end)

    config = [
      api_token: "tok",
      account_id: "acc",
      base_url: "http://localhost:#{port}",
      req_options: [receive_timeout: 50, retry: false]
    ]

    {time, result} = :timer.tc(fn -> Cloudflare.deliver(email(), config) end)

    assert {:error, %Req.TransportError{reason: :timeout}} = result
    assert time < 5_000_000
  end

  test "retry: false avoids retrying a failing request", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)

    config = Keyword.put(config, :req_options, retry: false)

    assert {:error, {503, :server_error, _}} = Cloudflare.deliver(email(), config)
  end

  test "supports a Req.Test plug" do
    Req.Test.stub(:cf_req_options, fn conn ->
      assert conn.request_path == "/client/v4" <> @path
      Req.Test.json(conn, %{"success" => true, "result" => %{"message_id" => "m9"}})
    end)

    config = [
      api_token: "tok",
      account_id: "acc",
      req_options: [plug: {Req.Test, :cf_req_options}]
    ]

    assert {:ok, %{id: "m9"}} = Cloudflare.deliver(email(), config)
  end

  test "req_options cannot override method or url", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, &ok_resp/1)

    config = Keyword.put(config, :req_options, method: :get, url: "http://invalid.example/x")

    assert {:ok, _} = Cloudflare.deliver(email(), config)
  end

  test "req_options apply to send_raw and Suppressions", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-trace") == ["abc"]
      ok_resp(conn)
    end)

    config = Keyword.put(config, :req_options, headers: [{"x-trace", "abc"}])

    assert {:ok, _} = SwooshCloudflare.send_raw("x", "a@example.com", ["b@example.com"], config)
    assert {:ok, _} = SwooshCloudflare.Suppressions.get("id1", config)
  end
end
