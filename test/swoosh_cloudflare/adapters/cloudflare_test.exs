defmodule Swoosh.Adapters.CloudflareTest do
  use ExUnit.Case, async: true

  alias Swoosh.Adapters.Cloudflare

  @config [
    api_token: "test-token",
    account_id: "test-account-id"
  ]

  defp base_email do
    %Swoosh.Email{
      to: [{"Alice", "alice@example.com"}],
      from: {"Sender", "sender@example.com"},
      subject: "Test Subject",
      html_body: "<p>Hello</p>"
    }
  end

  defp bypass_url(bypass), do: "http://localhost:#{bypass.port}"

  defp success_body(delivered \\ ["alice@example.com"]) do
    Jason.encode!(%{
      "success" => true,
      "result" => %{
        "delivered" => delivered,
        "permanent_bounces" => [],
        "queued" => []
      }
    })
  end

  defp expect_post(bypass, fun) do
    Bypass.expect_once(bypass, "POST", "/accounts/test-account-id/email/sending/send", fun)
  end

  setup do
    bypass = Bypass.open()
    config = Keyword.put(@config, :base_url, bypass_url(bypass))
    {:ok, bypass: bypass, config: config}
  end

  test "delivers email and returns delivered/permanent_bounces/queued", %{
    bypass: bypass,
    config: config
  } do
    expect_post(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    assert {:ok, %{delivered: ["alice@example.com"], permanent_bounces: [], queued: []}} =
             Cloudflare.deliver(base_email(), config)
  end

  test "sends correct payload fields", %{bypass: bypass, config: config} do
    expect_post(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["to"] == ["Alice <alice@example.com>"]
      assert payload["from"] == "Sender <sender@example.com>"
      assert payload["subject"] == "Test Subject"
      assert payload["html"] == "<p>Hello</p>"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    assert {:ok, _} = Cloudflare.deliver(base_email(), config)
  end

  test "sends Authorization header with Bearer token", %{bypass: bypass, config: config} do
    expect_post(bypass, fn conn ->
      assert {"authorization", "Bearer test-token"} in conn.req_headers

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    Cloudflare.deliver(base_email(), config)
  end

  test "sends cc, bcc, reply_to in payload", %{bypass: bypass, config: config} do
    email = %{
      base_email()
      | cc: [{"Bob", "bob@example.com"}],
        bcc: [{"", "bcc@example.com"}],
        reply_to: {"Reply", "reply@example.com"}
    }

    expect_post(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["cc"] == ["Bob <bob@example.com>"]
      assert payload["bcc"] == ["bcc@example.com"]
      assert payload["reply_to"] == "Reply <reply@example.com>"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    assert {:ok, _} = Cloudflare.deliver(email, config)
  end

  test "sends attachment with mimetype and base64 content", %{bypass: bypass, config: config} do
    attachment = %Swoosh.Attachment{
      filename: "doc.pdf",
      data: "PDF content",
      content_type: "application/pdf",
      type: :attachment,
      cid: nil
    }

    email = %{base_email() | attachments: [attachment]}

    expect_post(bypass, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [att] = Jason.decode!(body)["attachments"]

      assert att["filename"] == "doc.pdf"
      assert att["content"] == Base.encode64("PDF content")
      assert att["mimetype"] == "application/pdf"
      refute Map.has_key?(att, "contentType")
      refute Map.has_key?(att, "disposition")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    assert {:ok, _} = Cloudflare.deliver(email, config)
  end

  test "returns rate_limited with retry_after on 429", %{bypass: bypass, config: config} do
    expect_post(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "60")
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        429,
        Jason.encode!(%{
          "success" => false,
          "errors" => [%{"code" => 10004, "message" => "Rate limit exceeded"}]
        })
      )
    end)

    assert {:error, {429, :rate_limited, 60}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns rate_limited with nil retry_after when header absent", %{
    bypass: bypass,
    config: config
  } do
    expect_post(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        429,
        Jason.encode!(%{
          "success" => false,
          "errors" => [%{"code" => 10004, "message" => "Rate limit exceeded"}]
        })
      )
    end)

    assert {:error, {429, :rate_limited, nil}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns message_too_large error on 400 code 10202", %{bypass: bypass, config: config} do
    expect_post(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        400,
        Jason.encode!(%{
          "success" => false,
          "errors" => [%{"code" => 10202, "message" => "Message too large"}]
        })
      )
    end)

    assert {:error, {400, :message_too_large}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns server_error on 500", %{bypass: bypass, config: config} do
    expect_post(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        500,
        Jason.encode!(%{
          "success" => false,
          "errors" => [%{"code" => 10002, "message" => "Internal error"}]
        })
      )
    end)

    assert {:error, {500, :server_error}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns error tuple on network failure", %{bypass: bypass, config: config} do
    Bypass.down(bypass)

    assert {:error, _} = Cloudflare.deliver(base_email(), config)
  end

  test "deliver_many sends all emails and returns list of results", %{
    bypass: bypass,
    config: config
  } do
    emails = [
      base_email(),
      %{base_email() | to: [{"Bob", "bob@example.com"}]}
    ]

    Bypass.expect(bypass, "POST", "/accounts/test-account-id/email/sending/send", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, success_body())
    end)

    results = Cloudflare.deliver_many(emails, config)

    assert length(results) == 2
    assert Enum.all?(results, &match?({:ok, %{delivered: _}}, &1))
  end

  test "deliver_many collects errors without failing the batch", %{
    bypass: bypass,
    config: config
  } do
    emails = [base_email(), base_email()]

    Bypass.expect(bypass, "POST", "/accounts/test-account-id/email/sending/send", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        500,
        Jason.encode!(%{
          "success" => false,
          "errors" => [%{"code" => 10002, "message" => "Internal error"}]
        })
      )
    end)

    results = Cloudflare.deliver_many(emails, config)

    assert length(results) == 2
    assert Enum.all?(results, &match?({:error, {500, :server_error}}, &1))
  end
end
