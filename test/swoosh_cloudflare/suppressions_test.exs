defmodule SwooshCloudflare.SuppressionsTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Suppressions

  @base "/accounts/acc/email/sending/suppressions"

  setup do
    bypass = Bypass.open()
    config = [api_token: "tok", account_id: "acc", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  defp reply(conn, result, extra \\ %{}) do
    body = Map.merge(%{"success" => true, "errors" => [], "result" => result}, extra)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  defp json_body(conn) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(raw), conn}
  end

  test "list sends only given params and returns next_cursor", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base, fn conn ->
      assert URI.decode_query(conn.query_string) == %{
               "reason" => "hard_bounce",
               "per_page" => "50",
               "scope_type" => "sending_domain",
               "scope_value" => "mail.example.com",
               "cursor" => "c1"
             }

      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
      reply(conn, [%{"id" => "s1"}], %{"result_info" => %{"next_cursor" => "c2"}})
    end)

    assert {:ok, %{suppressions: [%{"id" => "s1"}], next_cursor: "c2"}} =
             Suppressions.list(config,
               reason: :hard_bounce,
               per_page: 50,
               scope_type: :sending_domain,
               scope_value: "mail.example.com",
               cursor: "c1"
             )
  end

  test "list without options has no query and nil cursor on last page", %{
    bypass: bypass,
    config: config
  } do
    Bypass.expect_once(bypass, "GET", @base, fn conn ->
      assert conn.query_string == ""
      reply(conn, [], %{"result_info" => %{"next_cursor" => nil}})
    end)

    assert {:ok, %{suppressions: [], next_cursor: nil}} = Suppressions.list(config)
  end

  test "list without result_info", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base, fn conn -> reply(conn, []) end)
    assert {:ok, %{next_cursor: nil}} = Suppressions.list(config, search: "x")
  end

  test "get", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base <> "/s1", fn conn ->
      reply(conn, %{"id" => "s1", "email" => "a@example.com"})
    end)

    assert {:ok, %{"id" => "s1"}} = Suppressions.get("s1", config)
  end

  test "create with sending_domain scope, note and expires_at", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @base, fn conn ->
      {body, conn} = json_body(conn)

      assert body == %{
               "email" => "a@example.com",
               "note" => "n",
               "expires_at" => "2030-01-01T00:00:00Z",
               "scope" => %{"type" => "sending_domain", "value" => "mail.example.com"}
             }

      reply(conn, %{"id" => "s1"})
    end)

    assert {:ok, %{"id" => "s1"}} =
             Suppressions.create("a@example.com", config,
               scope: {:sending_domain, "mail.example.com"},
               note: "n",
               expires_at: ~U[2030-01-01 00:00:00Z]
             )
  end

  test "create with only email omits optional fields", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @base, fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"email" => "a@example.com"}
      reply(conn, %{})
    end)

    assert {:ok, _} = Suppressions.create("a@example.com", config)
  end

  test "update omits absent keys", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "PATCH", @base <> "/s1", fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"note" => ""}
      reply(conn, %{})
    end)

    assert {:ok, _} = Suppressions.update("s1", config, note: "")
  end

  test "update sends null for expires_at: nil", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "PATCH", @base <> "/s1", fn conn ->
      {body, conn} = json_body(conn)
      assert body == %{"expires_at" => nil}
      assert Map.has_key?(body, "expires_at")
      reply(conn, %{})
    end)

    assert {:ok, _} = Suppressions.update("s1", config, expires_at: nil)
  end

  test "delete", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "DELETE", @base <> "/s1", fn conn ->
      reply(conn, %{"id" => "s1"})
    end)

    assert {:ok, %{"id" => "s1"}} = Suppressions.delete("s1", config)
  end

  test "import posts items", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @base <> "/bulk", fn conn ->
      {body, conn} = json_body(conn)

      assert body == %{
               "items" => [
                 %{"email" => "a@example.com", "scope" => %{"type" => "account"}},
                 %{"email" => "b@example.com", "note" => "x"}
               ]
             }

      reply(conn, %{"created" => 2})
    end)

    assert {:ok, %{"created" => 2}} =
             Suppressions.import(
               [%{email: "a@example.com", scope: :account}, [email: "b@example.com", note: "x"]],
               config
             )
  end

  test "import with more than 1000 items raises", %{config: config} do
    items = for i <- 1..1001, do: %{email: "u#{i}@example.com"}
    assert_raise ArgumentError, fn -> Suppressions.import(items, config) end
  end

  test "errors use shared tuples", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", @base <> "/nope", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(404, Jason.encode!(%{"errors" => [%{"code" => 10000}]}))
    end)

    assert {:error, {404, :not_found, _}} = Suppressions.get("nope", config)
  end

  test "rate limited", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "DELETE", @base <> "/s1", fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "5") |> Plug.Conn.send_resp(429, "")
    end)

    assert {:error, {429, :rate_limited, 5}} = Suppressions.delete("s1", config)
  end
end
