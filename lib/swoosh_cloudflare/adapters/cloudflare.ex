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

  ## Options

  - `:base_url` - overrides the Cloudflare API base URL.
  - `:req_options` - keyword list merged into the `Req` options of every request
    (adapter, `SwooshCloudflare.send_raw/4` and `SwooshCloudflare.Suppressions`).
    Use it for proxy, Finch pool, `connect_options`, `retry`, timeouts or
    `plug: {Req.Test, ...}`. Precedence is library defaults (`receive_timeout: 15_000`)
    < `:req_options` < per-call options. `method`, `url` and the Authorization header
    are always set by the library; extra `:headers` are appended.

        config :my_app, MyApp.Mailer,
          adapter: Swoosh.Adapters.Cloudflare,
          api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
          account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
          req_options: [receive_timeout: 30_000, retry: false]

  ## Provider options

  `Swoosh.Email.put_provider_option/3` values are merged into the JSON payload
  (keys converted to strings), overriding built fields. It is an escape hatch for API
  fields this adapter does not map yet:

      Swoosh.Email.put_provider_option(email, :some_new_field, "value")

  ## Success response

  `deliver/2` returns `{:ok, %{id: ..., delivered: [...], permanent_bounces: [...], queued: [...], suppressed_recipients: [...]}}`.

  - `id` is the Cloudflare message ID, which you can trace in the Email Service activity log.
  - `suppressed_recipients` lists recipients dropped because they are on the suppression list
    (only when "Drop suppressed recipients" is enabled on the sending domain). It is `[]` otherwise.

  ## Sending many emails

  `deliver_many/2` returns `{:ok, results}`, where `results` is a list with one
  `{:ok, map} | {:error, term}` per email, in input order.

  Emails are sent concurrently, up to `:max_concurrency` at a time (config key,
  default `System.schedulers_online()`). Each task is given the effective
  `receive_timeout` (from `:req_options`, default 15_000 ms) plus 5_000 ms; a task
  that exceeds it is killed and its result is `{:error, :timeout}`. A timeout result
  is ambiguous: the email may have been sent anyway.

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

  ## Header validation

  Custom headers are validated before any request is made. Headers Cloudflare
  controls (`Date`, `Message-ID`, `MIME-Version`, `Content-Type`,
  `Content-Transfer-Encoding`, `DKIM-Signature`, `Return-Path`, `Received`,
  `Feedback-ID`, `ARC-*`, `TLS-*`, `CFBL-*`) and headers that have a dedicated
  API field (`From`, `To`, `Cc`, `Bcc`, `Subject`, `Reply-To`) are rejected,
  case-insensitively, and no request is sent:

  - `{:error, {:invalid_header, header_name, :use_api_field}}`
  - `{:error, {:invalid_header, header_name, :not_allowed}}`
  - `{:error, {:invalid_header, header_name, :invalid_value}}` (a `nil`, empty or unconvertible value)

  Headers set through `provider_options` are validated the same way. Empty values
  and values that cannot be converted to a string are also `:invalid_value`.
  Non-string header values are converted with `to_string/1`. Cloudflare applies
  further rules of its own (for example only `X-*` and a fixed set of standard
  headers are accepted); those are reported by the API as usual.
  See `SwooshCloudflare.put_list_unsubscribe/3` for one-click unsubscribe.

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

  alias SwooshCloudflare.{Client, EmailBuilder, Headers}

  @typedoc "Successful send result."
  @type send_result :: %{
          id: String.t() | nil,
          delivered: [String.t()],
          permanent_bounces: [String.t()],
          queued: [String.t()],
          suppressed_recipients: [String.t()]
        }

  @typedoc """
  Error returned by `deliver/2` and `SwooshCloudflare.send_raw/4`.

  Besides the tuples below, transport errors (for example `Req.TransportError`)
  are passed through unchanged.
  """
  @type error ::
          {:invalid_header, String.t(), :use_api_field | :not_allowed | :invalid_value}
          | {429, :rate_limited, non_neg_integer() | nil}
          | {pos_integer(), :invalid_response, term()}
          | {pos_integer(), atom(), term()}
          | Exception.t()
          | term()

  @impl true
  @spec deliver(Swoosh.Email.t(), keyword()) :: {:ok, send_result()} | {:error, error()}
  def deliver(%Swoosh.Email{} = email, config) do
    payload = EmailBuilder.build(email)

    with {:ok, payload} <- validate_headers(payload) do
      Client.send(payload, config)
    end
  end

  # Validates the final payload, so headers coming from provider options are covered too.
  defp validate_headers(%{"headers" => headers} = payload) do
    with {:ok, headers} <- Headers.validate(headers) do
      if headers == %{},
        do: {:ok, Map.delete(payload, "headers")},
        else: {:ok, Map.put(payload, "headers", headers)}
    end
  end

  defp validate_headers(payload), do: {:ok, payload}

  @impl true
  @spec deliver_many([Swoosh.Email.t()], keyword()) ::
          {:ok, [{:ok, send_result()} | {:error, error() | :timeout}]} | {:error, error()}
  def deliver_many(emails, config) do
    results =
      emails
      |> Task.async_stream(&deliver(&1, config),
        max_concurrency: Keyword.get(config, :max_concurrency, System.schedulers_online()),
        timeout: task_timeout(config),
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {:error, :timeout}
      end)

    {:ok, results}
  end

  # Effective receive_timeout (from :req_options, default 15_000) plus a margin.
  defp task_timeout(config) do
    receive_timeout =
      config |> Keyword.get(:req_options, []) |> Keyword.get(:receive_timeout, 15_000)

    if receive_timeout == :infinity, do: :infinity, else: receive_timeout + 5_000
  end
end
