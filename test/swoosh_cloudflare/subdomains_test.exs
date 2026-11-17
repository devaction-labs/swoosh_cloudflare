defmodule SwooshCloudflare.SubdomainsTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Subdomains

  @base "/zones/zone1/email/sending/subdomains"

  setup do
    bypass = Bypass.open()
    # No :account_id on purpose: subdomains are zone-scoped.
    config = [api_token: "tok", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  defp reply(conn, result) do
    body = %{"success" => true, "errors" => [], "result" => result}

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  defp json_body(conn) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(raw), conn}
  end

  @subdomain %{
    "tag" => "sub1",
    "name" => "send.example.com",
    "enabled" => true,
    "drop_suppressed_recipients" => false,
    "preview_enabled" => false
  }

  test "list returns the subdomains", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
      reply(conn, [@subdomain])
    end)

    assert {:ok, [%{"tag" => "sub1"}]} = Subdomains.list("zone1", config)
  end

  test "get fetches one and url-encodes the id", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base <> "/a%2Fb", fn conn ->
      assert conn.request_path == @base <> "/a%2Fb"
      reply(conn, @subdomain)
    end)

    assert {:ok, %{"name" => "send.example.com"}} = Subdomains.get("zone1", "a/b", config)
  end

  test "create posts the name", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @base, fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"name" => "send.example.com"}
      reply(conn, @subdomain)
    end)

    assert {:ok, %{"tag" => "sub1"}} = Subdomains.create("zone1", "send.example.com", config)
  end

  test "update sends only the given documented fields", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "PATCH", @base <> "/sub1", fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"drop_suppressed_recipients" => true}
      reply(conn, Map.put(@subdomain, "drop_suppressed_recipients", true))
    end)

    assert {:ok, %{"drop_suppressed_recipients" => true}} =
             Subdomains.update("zone1", "sub1", config,
               drop_suppressed_recipients: true,
               ignored: 1
             )
  end

  test "update can send both fields", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "PATCH", @base <> "/sub1", fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"drop_suppressed_recipients" => false, "preview_enabled" => true}
      reply(conn, @subdomain)
    end)

    assert {:ok, _} =
             Subdomains.update("zone1", "sub1", config,
               drop_suppressed_recipients: false,
               preview_enabled: true
             )
  end

  test "delete", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "DELETE", @base <> "/sub1", fn conn -> reply(conn, nil) end)
    assert {:ok, nil} = Subdomains.delete("zone1", "sub1", config)
  end

  test "dns_records returns the list", %{bypass: bypass, config: config} do
    record = %{"type" => "TXT", "name" => "send.example.com", "content" => "v=spf1 ~all"}

    Bypass.expect_once(bypass, "GET", @base <> "/sub1/dns", fn conn -> reply(conn, [record]) end)

    assert {:ok, [^record]} = Subdomains.dns_records("zone1", "sub1", config)
  end

  test "maps API errors and rate limits like the rest of the library", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "GET", @base <> "/nope", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, Jason.encode!(%{"success" => false, "errors" => []}))
    end)

    assert {:error, {404, _reason, _body}} = Subdomains.get("zone1", "nope", config)

    Bypass.expect_once(bypass, "DELETE", @base <> "/sub1", fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "7") |> Plug.Conn.send_resp(429, "")
    end)

    assert {:error, {429, :rate_limited, 7}} = Subdomains.delete("zone1", "sub1", config)
  end

  test "requires only api_token", %{config: config} do
    assert_raise ArgumentError, ~r/:api_token/, fn ->
      Subdomains.list("zone1", Keyword.delete(config, :api_token))
    end
  end
end
