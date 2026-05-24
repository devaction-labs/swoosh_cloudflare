defmodule Swoosh.Adapters.Cloudflare do
  @moduledoc """
  Swoosh adapter for Cloudflare Email Service REST API.

  ## Configuration

      config :my_app, MyApp.Mailer,
        adapter: Swoosh.Adapters.Cloudflare,
        api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
        account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")

  ## Limitations

  - New accounts can only send to verified addresses. Paid plans unlock general sending.
  - The `from` address must belong to a domain with Email Routing active in the Cloudflare account.
  - Maximum 50 recipients per email.
  - Maximum message size: 5 MiB.
  """

  use Swoosh.Adapter, required_config: [:api_token, :account_id]

  alias SwooshCloudflare.{Client, EmailBuilder}

  @impl true
  def deliver(%Swoosh.Email{} = email, config) do
    payload = EmailBuilder.build(email)
    Client.send(payload, config)
  end
end
