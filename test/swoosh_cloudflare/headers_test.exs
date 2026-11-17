defmodule SwooshCloudflare.HeadersTest do
  use ExUnit.Case, async: true

  alias Swoosh.Adapters.Cloudflare
  alias SwooshCloudflare.Headers

  defp email(headers) do
    Enum.reduce(
      headers,
      %Swoosh.Email{
        to: [{"Alice", "alice@example.com"}],
        from: {"Sender", "sender@example.com"},
        subject: "Hi",
        html_body: "<p>Hi</p>"
      },
      fn {k, v}, acc -> %{acc | headers: Map.put(acc.headers, k, v)} end
    )
  end

  describe "Headers.validate/1" do
    test "accepts nil and custom headers" do
      assert {:ok, %{}} = Headers.validate(nil)

      assert {:ok, %{"X-Foo" => "bar", "In-Reply-To" => "<a@b>"}} =
               Headers.validate(%{"X-Foo" => "bar", "In-Reply-To" => "<a@b>"})
    end

    test "stringifies non-binary values" do
      assert {:ok, %{"X-Count" => "3", "X-Flag" => "true"}} =
               Headers.validate(%{"X-Count" => 3, "X-Flag" => true})
    end

    test "rejects nil values" do
      assert {:error, {:invalid_header, "X-Foo", :invalid_value}} =
               Headers.validate(%{"X-Foo" => nil})
    end

    test "rejects platform-controlled headers case-insensitively" do
      for name <-
            ~w(Date message-id MIME-Version CONTENT-TYPE Content-Transfer-Encoding
                     DKIM-Signature Return-Path Received Feedback-ID ARC-Seal arc-message-signature
                     TLS-Required TLS-Report-Domain TLS-Report-Submitter CFBL-Address cfbl-feedback-id) do
        assert {:error, {:invalid_header, ^name, :not_allowed}} = Headers.validate(%{name => "x"})
      end
    end

    test "rejects headers that have an API field" do
      for name <- ~w(From To Cc BCC subject Reply-To) do
        assert {:error, {:invalid_header, ^name, :use_api_field}} =
                 Headers.validate(%{name => "x"})
      end
    end
  end

  describe "deliver/2 validation" do
    test "returns the error and makes no request" do
      # Nothing listens here, so a request would return a transport error instead.
      config = [api_token: "t", account_id: "a", base_url: "http://localhost:1"]

      assert {:error, {:invalid_header, "Message-ID", :not_allowed}} =
               Cloudflare.deliver(email([{"Message-ID", "<x@y>"}]), config)

      assert {:error, {:invalid_header, "subject", :use_api_field}} =
               Cloudflare.deliver(email([{"subject", "x"}]), config)
    end

    test "sends valid headers stringified" do
      bypass = Bypass.open()
      config = [api_token: "t", account_id: "a", base_url: "http://localhost:#{bypass.port}"]

      Bypass.expect_once(bypass, "POST", "/accounts/a/email/sending/send", fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(raw)["headers"] == %{"X-Count" => "2", "X-Foo" => "bar"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"success" => true, "result" => %{}}))
      end)

      assert {:ok, _} = Cloudflare.deliver(email([{"X-Foo", "bar"}, {"X-Count", 2}]), config)
    end
  end

  describe "SwooshCloudflare.put_list_unsubscribe/3" do
    test "sets both headers by default" do
      email = SwooshCloudflare.put_list_unsubscribe(email([]), "https://example.com/u/1")

      assert email.headers == %{
               "List-Unsubscribe" => "<https://example.com/u/1>",
               "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
             }
    end

    test "adds the mailto entry" do
      email =
        SwooshCloudflare.put_list_unsubscribe(email([]), "https://example.com/u/1",
          mailto: "unsub@example.com"
        )

      assert email.headers["List-Unsubscribe"] ==
               "<https://example.com/u/1>, <mailto:unsub@example.com>"
    end

    test "one_click: false skips the Post header" do
      email =
        SwooshCloudflare.put_list_unsubscribe(email([]), "https://example.com/u/1",
          one_click: false
        )

      assert Map.keys(email.headers) == ["List-Unsubscribe"]
    end

    test "raises for non-https URLs" do
      assert_raise ArgumentError, fn ->
        SwooshCloudflare.put_list_unsubscribe(email([]), "http://example.com/u")
      end

      assert_raise ArgumentError, fn ->
        SwooshCloudflare.put_list_unsubscribe(email([]), "mailto:a@example.com")
      end
    end

    test "produces headers that pass validation" do
      email = SwooshCloudflare.put_list_unsubscribe(email([]), "https://example.com/u/1")
      assert {:ok, _} = Headers.validate(email.headers)
    end
  end
end
