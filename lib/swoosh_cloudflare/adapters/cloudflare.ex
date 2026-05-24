defmodule Swoosh.Adapters.Cloudflare do
  @moduledoc """
  Swoosh adapter for Cloudflare Email Service REST API.

  ## Configuration

      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.Cloudflare,
        api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
        account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")

  ## Success response

  `deliver/2` returns `{:ok, %{delivered: [...], permanent_bounces: [...], queued: [...]}}`.

  ## Error responses

  `deliver/2` returns `{:error, {status, reason}}` for most errors, and
  `{:error, {429, :rate_limited, retry_after_seconds}}` for rate limiting,
  where `retry_after_seconds` is an integer or `nil` if the header was absent.

  ## Limitations

  - New accounts can only send to verified addresses. Paid plans unlock general sending.
  - The `from` address must belong to a domain with Email Routing active in the Cloudflare account.
  - Maximum 50 recipients per email (combined to/cc/bcc).
  - Maximum message size: 5 MiB (25 MiB for verified accounts).
  - Transactional email only — bulk/marketing sending is not supported.
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
  @spec deliver_many([Swoosh.Email.t()], keyword()) :: [{:ok, map()} | {:error, term()}]
  def deliver_many(emails, config) do
    emails
    |> Task.async_stream(&deliver(&1, config), timeout: 30_000, on_timeout: :kill_task)
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> {:error, :timeout}
    end)
  end
end
