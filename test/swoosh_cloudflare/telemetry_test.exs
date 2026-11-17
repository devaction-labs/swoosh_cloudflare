defmodule SwooshCloudflare.TelemetryTest do
  # Not async: telemetry handlers are global.
  use ExUnit.Case, async: false

  alias Swoosh.Adapters.Cloudflare

  @path "/accounts/acc/email/sending/send"

  setup do
    bypass = Bypass.open()

    config = [
      api_token: "secret-token",
      account_id: "acc",
      base_url: "http://localhost:#{bypass.port}",
      req_options: [retry: false]
    ]

    id = "telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach_many(
      id,
      [
        [:swoosh_cloudflare, :request, :start],
        [:swoosh_cloudflare, :request, :stop],
        [:swoosh_cloudflare, :request, :exception]
      ],
      &__MODULE__.handle_event/4,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(id) end)

    {:ok, bypass: bypass, config: config}
  end

  def handle_event(event, measurements, meta, test_pid),
    do: send(test_pid, {:event, event, measurements, meta})

  defp email do
    %Swoosh.Email{
      to: ["alice@example.com"],
      from: "sender@example.com",
      subject: "Hi",
      html_body: "<p>Hi</p>"
    }
  end

  test "emits start and stop with status and result on success", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"success" => true, "result" => %{}}))
    end)

    assert {:ok, _} = Cloudflare.deliver(email(), config)

    assert_receive {:event, [:swoosh_cloudflare, :request, :start], _, start_meta}
    assert Map.delete(start_meta, :telemetry_span_context) == %{method: :post, path: "/send"}

    assert_receive {:event, [:swoosh_cloudflare, :request, :stop], %{duration: duration}, meta}
    assert is_integer(duration)

    assert Map.delete(meta, :telemetry_span_context) ==
             %{method: :post, path: "/send", status: 200, result: :ok}
  end

  test "reports the HTTP status on error responses", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", @path, &Plug.Conn.send_resp(&1, 429, ""))

    assert {:error, {429, :rate_limited, nil}} = Cloudflare.deliver(email(), config)

    assert_receive {:event, [:swoosh_cloudflare, :request, :stop], _, meta}
    assert meta.status == 429
    assert meta.result == :error
  end

  test "status is nil on transport errors and no secrets are exposed", %{
    bypass: bypass,
    config: config
  } do
    Bypass.down(bypass)

    assert {:error, _} = Cloudflare.deliver(email(), config)

    assert_receive {:event, [:swoosh_cloudflare, :request, :stop], _, meta}
    assert meta.status == nil
    assert meta.result == :error
    refute inspect(meta) =~ "secret-token"

    assert Enum.sort(Map.keys(Map.delete(meta, :telemetry_span_context))) == [
             :method,
             :path,
             :result,
             :status
           ]
  end

  test "emits for other client calls", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", "/accounts/acc/email/sending/suppressions/x", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"success" => true, "result" => %{}}))
    end)

    assert {:ok, _} = SwooshCloudflare.Suppressions.get("x", config)

    assert_receive {:event, [:swoosh_cloudflare, :request, :stop], _,
                    %{method: :get, path: "/suppressions/x", status: 200}}
  end

  test "invalid UTF-8 in send_raw raises without a telemetry exception event", %{config: config} do
    assert_raise Jason.EncodeError, fn ->
      SwooshCloudflare.send_raw(
        <<0xFF, 0xFE, "secret">>,
        "a@example.com",
        ["b@example.com"],
        config
      )
    end

    refute_receive {:event, [:swoosh_cloudflare, :request, :exception], _, _}, 50
    refute_receive {:event, [:swoosh_cloudflare, :request, :start], _, _}, 50
  end
end
