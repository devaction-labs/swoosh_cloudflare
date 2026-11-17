defmodule SwooshCloudflare do
  @moduledoc """
  Helpers for the Cloudflare Email Service beyond `Swoosh.Adapters.Cloudflare`.

  - `send_raw/4` sends a pre-built MIME message.
  - `put_list_unsubscribe/3` sets the one-click unsubscribe headers.
  - `SwooshCloudflare.Suppressions` manages the suppression list.

  All functions take the same `config` keyword list as the mailer
  (`:api_token`, `:account_id`, and optionally `:base_url`):

      config = Application.get_env(:my_app, MyApp.Mailer)
  """

  alias SwooshCloudflare.Client

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

  @doc """
  Sets the `List-Unsubscribe` header, and by default `List-Unsubscribe-Post`
  for RFC 8058 one-click unsubscribe.

  `url` must be an `https://` URL, otherwise `ArgumentError` is raised.

  Options:

    * `:mailto` - an address added as a `<mailto:...>` entry
    * `:one_click` - when `false`, `List-Unsubscribe-Post` is not set (default `true`)

  ## Example

      email
      |> SwooshCloudflare.put_list_unsubscribe("https://example.com/unsubscribe/abc",
        mailto: "unsubscribe@example.com"
      )

  sets `List-Unsubscribe` to
  `<https://example.com/unsubscribe/abc>, <mailto:unsubscribe@example.com>` and
  `List-Unsubscribe-Post` to `List-Unsubscribe=One-Click`.
  """
  @spec put_list_unsubscribe(Swoosh.Email.t(), String.t(), keyword()) :: Swoosh.Email.t()
  def put_list_unsubscribe(%Swoosh.Email{} = email, url, opts \\ []) do
    unless is_binary(url) and String.starts_with?(url, "https://") do
      raise ArgumentError, "expected an https:// URL, got: #{inspect(url)}"
    end

    entries =
      case Keyword.get(opts, :mailto) do
        nil -> ["<#{url}>"]
        mailto -> ["<#{url}>", "<mailto:#{String.replace_prefix(mailto, "mailto:", "")}>"]
      end

    email = Swoosh.Email.header(email, "List-Unsubscribe", Enum.join(entries, ", "))

    if Keyword.get(opts, :one_click, true) do
      Swoosh.Email.header(email, "List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    else
      email
    end
  end
end
