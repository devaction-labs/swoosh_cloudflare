defmodule SwooshCloudflare.SendRawTest do
  use ExUnit.Case, async: true

  @path "/accounts/acc/email/sending/send_raw"

  setup do
    bypass = Bypass.open()
    config = [api_token: "tok", account_id: "acc", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  test "posts the raw message and returns the send result", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(raw) == %{
               "from" => "a@example.com",
               "recipients" => ["b@example.com", "c@example.com"],
               "mime_message" => "Subject: Hi\r\n\r\nBody"
             }

      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]

      body = %{
        "success" => true,
        "result" => %{"message_id" => "m1", "delivered" => ["b@example.com"], "queued" => []}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end)

    assert {:ok,
            %{
              id: "m1",
              delivered: ["b@example.com"],
              permanent_bounces: [],
              queued: [],
              suppressed_recipients: []
            }} =
             SwooshCloudflare.send_raw(
               "Subject: Hi\r\n\r\nBody",
               "a@example.com",
               ["b@example.com", "c@example.com"],
               config
             )
  end

  test "maps API errors", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(400, Jason.encode!(%{"errors" => [%{"code" => 10202}]}))
    end)

    assert {:error, {400, :invalid_email, %{"errors" => _}}} =
             SwooshCloudflare.send_raw("x", "a@example.com", ["b@example.com"], config)
  end

  test "maps rate limiting", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "30") |> Plug.Conn.send_resp(429, "")
    end)

    assert {:error, {429, :rate_limited, 30}} =
             SwooshCloudflare.send_raw("x", "a@example.com", ["b@example.com"], config)
  end

  test "returns network errors", %{bypass: bypass, config: config} do
    Bypass.down(bypass)

    assert {:error, _} =
             SwooshCloudflare.send_raw("x", "a@example.com", ["b@example.com"], config)
  end

  test "raises on missing config" do
    assert_raise ArgumentError, fn ->
      SwooshCloudflare.send_raw("x", "a@example.com", ["b@example.com"], api_token: "t")
    end
  end
end
