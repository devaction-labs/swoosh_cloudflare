defmodule SwooshCloudflare.AnalyticsTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Analytics

  setup do
    bypass = Bypass.open()
    # No :account_id on purpose: the GraphQL endpoint is not account-scoped.
    config = [api_token: "tok", base_url: "http://localhost:#{bypass.port}"]
    {:ok, bypass: bypass, config: config}
  end

  defp reply(conn, body, status \\ 200) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp json_body(conn) do
    {:ok, raw, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(raw), conn}
  end

  describe "query/3" do
    test "posts query and variables to /graphql and returns data", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        {body, conn} = json_body(conn)
        assert body == %{"query" => "{ viewer { zones } }", "variables" => %{"a" => 1}}
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]
        reply(conn, %{"data" => %{"viewer" => %{"zones" => []}}, "errors" => nil})
      end)

      assert {:ok, %{"viewer" => %{"zones" => []}}} =
               Analytics.query("{ viewer { zones } }", %{"a" => 1}, config)
    end

    test "nil variables become an empty map", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        {body, conn} = json_body(conn)
        assert body["variables"] == %{}
        reply(conn, %{"data" => %{}, "errors" => []})
      end)

      assert {:ok, %{}} = Analytics.query("{ a }", nil, config)
    end

    test "GraphQL errors in a 200 response are an error", %{bypass: bypass, config: config} do
      errors = [%{"message" => "unknown field", "path" => ["viewer"]}]

      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        reply(conn, %{"data" => nil, "errors" => errors})
      end)

      assert {:error, {200, :graphql_error, ^errors}} = Analytics.query("{ a }", %{}, config)
    end

    test "maps HTTP errors like the rest of the library", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        reply(conn, %{"success" => false, "errors" => [%{"code" => 10000}]}, 403)
      end)

      assert {:error, {403, _reason, _body}} = Analytics.query("{ a }", %{}, config)
    end

    test "requires only api_token", %{config: config} do
      assert_raise ArgumentError, ~r/:api_token/, fn ->
        Analytics.query("{ a }", %{}, Keyword.delete(config, :api_token))
      end
    end
  end

  describe "message_events/4" do
    test "queries emailSendingAdaptive and returns the rows", %{bypass: bypass, config: config} do
      row = %{"datetime" => "2026-06-01T02:48:57Z", "status" => "delivered", "messageId" => "m1"}

      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        {body, conn} = json_body(conn)
        assert body["query"] =~ "emailSendingAdaptive("
        assert body["query"] =~ "messageId: $messageId"
        assert body["query"] =~ "datetime_geq: $start"
        assert body["query"] =~ "orderBy: [datetime_DESC]"

        assert %{
                 "zoneTag" => "zone1",
                 "messageId" => "m1",
                 "start" => "2026-06-01T00:00:00Z",
                 "end" => "2026-06-02T00:00:00Z",
                 "limit" => 5
               } = body["variables"]

        reply(conn, %{
          "data" => %{"viewer" => %{"zones" => [%{"emailSendingAdaptive" => [row]}]}},
          "errors" => nil
        })
      end)

      assert {:ok, [^row]} =
               Analytics.message_events("zone1", "m1", config,
                 start: ~U[2026-06-01 00:00:00Z],
                 end: ~U[2026-06-02 00:00:00Z],
                 limit: 5
               )
    end

    test "defaults to the last 24 hours and 100 rows", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        {body, conn} = json_body(conn)
        %{"start" => s, "end" => e, "limit" => 100} = body["variables"]
        {:ok, s, _} = DateTime.from_iso8601(s)
        {:ok, e, _} = DateTime.from_iso8601(e)
        assert DateTime.diff(e, s) == 86_400
        reply(conn, %{"data" => %{"viewer" => %{"zones" => []}}, "errors" => nil})
      end)

      assert {:ok, []} = Analytics.message_events("zone1", "m1", config)
    end

    test "returns [] when the zone has no rows", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        reply(conn, %{
          "data" => %{"viewer" => %{"zones" => [%{"emailSendingAdaptive" => []}]}},
          "errors" => nil
        })
      end)

      assert {:ok, []} = Analytics.message_events("zone1", "m1", config)
    end

    test "propagates GraphQL errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/graphql", fn conn ->
        reply(conn, %{"data" => nil, "errors" => [%{"message" => "bad filter"}]})
      end)

      assert {:error, {200, :graphql_error, [%{"message" => "bad filter"}]}} =
               Analytics.message_events("zone1", "m1", config)
    end
  end
end
