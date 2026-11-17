defmodule Swoosh.Adapters.Cloudflare do
  @moduledoc """
  Swoosh adapter for Cloudflare Email Service REST API.

  ## Configuration

  Put this in `config/runtime.exs`, since it reads environment variables. This adapter
  uses Req directly, so also set `config :swoosh, :api_client, false` in `config/config.exs`.

      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.Cloudflare,
        api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
        account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")

  ## Success response

  `deliver/2` returns `{:ok, %{id: ..., delivered: [...], permanent_bounces: [...], queued: [...], suppressed_recipients: [...]}}`.

  - `id` is the Cloudflare message ID, which you can trace in the Email Service activity log.
  - `suppressed_recipients` lists recipients dropped because they are on the suppression list
    (only when "Drop suppressed recipients" is enabled on the sending domain). It is `[]` otherwise.

  ## Sending many emails

  `deliver_many/2` returns `{:ok, results}`, where `results` is a list with one
  `{:ok, map} | {:error, term}` per email, in input order.

  ## Inline images

  Use `type: :inline` with a `cid`, e.g.
  `Swoosh.Attachment.new("logo.png", type: :inline, cid: "logo")`, and reference it
  in the HTML body with `<img src="cid:logo">`.

  ## Error responses

  `deliver/2` returns `{:error, {status, reason, body}}` for most errors, with
  Cloudflare's response body so its message is not lost, and
  `{:error, {429, :rate_limited, retry_after_seconds}}` for rate limiting,
  where `retry_after_seconds` is an integer or `nil` if the header was absent.
  Any 2xx with a JSON body is success; a 2xx without one is
  `{:error, {status, :invalid_response, body}}`.

  ## Limitations

  - Maximum total message size is 25 MiB, including attachments.
  - Maximum 50 recipients per email (combined to/cc/bcc).
  - Subject: maximum 998 characters.
  - Custom headers: maximum 16 KB combined.
  - Before onboarding a sending domain, you can only send to verified destination addresses. After onboarding a sending domain, you can send to any recipient.
  - The `from` address must be on an onboarded sending domain.
  - Transactional email only. Bulk/marketing sending is not supported.
  """

  use Swoosh.Adapter, required_config: [:api_token, :account_id]

  alias SwooshCloudflare.{Client, EmailBuilder}

  @impl true
  @spec deliver(Swoosh.Email.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def deliver(%Swoosh.Email{} = email, config) do
    payload = EmailBuilder.build(email)
    Client.send(payload, config)
  end

  @impl true
  @spec deliver_many([Swoosh.Email.t()], keyword()) ::
          {:ok, [{:ok, map()} | {:error, term()}]} | {:error, term()}
  def deliver_many(emails, config) do
    results =
      emails
      |> Task.async_stream(&deliver(&1, config), timeout: 30_000, on_timeout: :kill_task)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {:error, :timeout}
      end)

    {:ok, results}
  end
end
