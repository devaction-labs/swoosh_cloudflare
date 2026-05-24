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

  setup do
    bypass = Bypass.open()
    config = Keyword.put(@config, :base_url, bypass_url(bypass))
    {:ok, bypass: bypass, config: config}
  end

  test "delivers simple email and returns ok", %{bypass: bypass, config: config} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["to"] == ["Alice <alice@example.com>"]
        assert payload["from"] == "Sender <sender@example.com>"
        assert payload["subject"] == "Test Subject"
        assert payload["html"] == "<p>Hello</p>"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "success" => true,
            "result" => %{
              "delivered" => ["alice@example.com"],
              "permanent_bounces" => [],
              "queued" => []
            }
          })
        )
      end
    )

    assert {:ok, %{id: ["alice@example.com"]}} = Cloudflare.deliver(base_email(), config)
  end

  test "sends Authorization header with Bearer token", %{bypass: bypass, config: config} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        assert {"authorization", "Bearer test-token"} in conn.req_headers

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "success" => true,
            "result" => %{
              "delivered" => ["alice@example.com"],
              "permanent_bounces" => [],
              "queued" => []
            }
          })
        )
      end
    )

    Cloudflare.deliver(base_email(), config)
  end

  test "sends cc, bcc, reply_to in payload", %{bypass: bypass, config: config} do
    email = %{
      base_email()
      | cc: [{"Bob", "bob@example.com"}],
        bcc: [{"", "bcc@example.com"}],
        reply_to: {"Reply", "reply@example.com"}
    }

    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["cc"] == ["Bob <bob@example.com>"]
        assert payload["bcc"] == ["bcc@example.com"]
        assert payload["reply_to"] == "Reply <reply@example.com>"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "success" => true,
            "result" => %{
              "delivered" => ["alice@example.com"],
              "permanent_bounces" => [],
              "queued" => []
            }
          })
        )
      end
    )

    assert {:ok, _} = Cloudflare.deliver(email, config)
  end

  test "encodes attachment content as base64", %{bypass: bypass, config: config} do
    attachment = %Swoosh.Attachment{
      filename: "doc.pdf",
      data: "PDF content",
      content_type: "application/pdf",
      type: :attachment,
      cid: nil
    }

    email = %{base_email() | attachments: [attachment]}

    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        [att] = payload["attachments"]

        assert att["content"] == Base.encode64("PDF content")
        assert att["disposition"] == "attachment"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "success" => true,
            "result" => %{
              "delivered" => ["alice@example.com"],
              "permanent_bounces" => [],
              "queued" => []
            }
          })
        )
      end
    )

    assert {:ok, _} = Cloudflare.deliver(email, config)
  end

  test "sends inline image with disposition and contentId", %{bypass: bypass, config: config} do
    attachment = %Swoosh.Attachment{
      filename: "logo.png",
      data: "PNG data",
      content_type: "image/png",
      type: :inline,
      cid: "logo@example.com"
    }

    email = %{base_email() | attachments: [attachment]}

    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [att] = Jason.decode!(body)["attachments"]

        assert att["disposition"] == "inline"
        assert att["contentId"] == "logo@example.com"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "success" => true,
            "result" => %{
              "delivered" => ["alice@example.com"],
              "permanent_bounces" => [],
              "queued" => []
            }
          })
        )
      end
    )

    assert {:ok, _} = Cloudflare.deliver(email, config)
  end

  test "returns rate_limited error on 429", %{bypass: bypass, config: config} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          429,
          Jason.encode!(%{
            "success" => false,
            "errors" => [%{"code" => 10004, "message" => "Rate limit exceeded"}]
          })
        )
      end
    )

    assert {:error, {429, :rate_limited}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns message_too_large error on 400 code 10202", %{bypass: bypass, config: config} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          400,
          Jason.encode!(%{
            "success" => false,
            "errors" => [%{"code" => 10202, "message" => "Message too large"}]
          })
        )
      end
    )

    assert {:error, {400, :message_too_large}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns server_error on 500", %{bypass: bypass, config: config} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/accounts/test-account-id/email/sending/send",
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          500,
          Jason.encode!(%{
            "success" => false,
            "errors" => [%{"code" => 10002, "message" => "Internal error"}]
          })
        )
      end
    )

    assert {:error, {500, :server_error}} = Cloudflare.deliver(base_email(), config)
  end

  test "returns error tuple on network failure", %{bypass: bypass, config: config} do
    Bypass.down(bypass)

    assert {:error, _} = Cloudflare.deliver(base_email(), config)
  end
end
