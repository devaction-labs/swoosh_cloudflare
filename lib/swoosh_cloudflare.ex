defmodule SwooshCloudflare do
  @moduledoc """
  Helpers for the Cloudflare Email Service beyond `Swoosh.Adapters.Cloudflare`.

  - `send_raw/4` sends a pre-built MIME message.
  - `SwooshCloudflare.Suppressions` manages the suppression list.

  All functions take the same `config` keyword list as the mailer
  (`:api_token`, `:account_id`, and optionally `:base_url`):

      config = Application.get_env(:my_app, MyApp.Mailer)
  """

  alias SwooshCloudflare.Client

  @doc """
  Hello world.

  ## Examples

      iex> SwooshCloudflare.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Sends a full RFC 5322 MIME message through the `send_raw` endpoint.

  `from` is the envelope sender and `recipients` the envelope recipients.

  Returns the same values as the mailer when using `Swoosh.Adapters.Cloudflare`:
  `{:ok, %{id: ..., delivered: [...], permanent_bounces: [...], queued: [...], suppressed_recipients: [...]}}`,
  `{:error, {status, reason, body}}` or `{:error, {429, :rate_limited, retry_after}}`.

  Raises `ArgumentError` if `:api_token` or `:account_id` is missing from `config`.

  ## Example

      SwooshCloudflare.send_raw(mime, "noreply@example.com", ["alice@example.com"], config)
  """
  @spec send_raw(String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def send_raw(mime_message, from, recipients, config)
      when is_binary(mime_message) and is_binary(from) and is_list(recipients) do
    Client.send_raw(
      %{"from" => from, "recipients" => recipients, "mime_message" => mime_message},
      config
    )
  end
end
