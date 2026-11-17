# SwooshCloudflare

[Swoosh](https://github.com/swoosh/swoosh) adapter for [Cloudflare Email Service](https://developers.cloudflare.com/email-service/).

> **Note:** Cloudflare Email Service is currently in **beta**. The API may change before general availability. Check the [official documentation](https://developers.cloudflare.com/email-service/) for the latest updates.

## Installation

```elixir
def deps do
  [
    {:swoosh_cloudflare, "~> 0.7"}
  ]
end
```

## Getting your Cloudflare credentials

You need two values: an **Account ID** and an **API Token**.

### Account ID

1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com)
2. Select any domain (or go to the account home page)
3. Your **Account ID** is shown on the right sidebar under "Account ID"

### API Token

You need a token with permission to send emails via the Email Service API.

1. Go to [My Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use **Create Custom Token**
4. Add the permission: **Account → Email Sending — Send**
5. Under **Account Resources**, select your account
6. Click **Continue to summary → Create Token**
7. Copy the token — it is shown only once

Set both values as environment variables:

```bash
CLOUDFLARE_EMAIL_TOKEN=your_api_token_here
CLOUDFLARE_ACCOUNT_ID=your_account_id_here
```

## Configuration

Read the secrets at runtime, in `config/runtime.exs`:

```elixir
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Cloudflare,
  api_token: System.fetch_env!("CLOUDFLARE_EMAIL_TOKEN"),
  account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID")
```

This adapter uses [Req](https://hex.pm/packages/req) directly, so Swoosh's default
Hackney API client is not needed. Disable it in `config/config.exs`:

```elixir
config :swoosh, :api_client, false
```

Optional `:req_options` (a keyword list) are merged into the [Req](https://hexdocs.pm/req) options of every request, for the adapter, `send_raw/4` and `Suppressions`. Use it for a proxy, Finch pool, `connect_options`, `retry`, timeouts or `plug: {Req.Test, ...}`:

```elixir
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Cloudflare,
  api_token: System.fetch_env!("CLOUDFLARE_EMAIL_TOKEN"),
  account_id: System.fetch_env!("CLOUDFLARE_ACCOUNT_ID"),
  req_options: [receive_timeout: 30_000, retry: false]
```

Precedence is library defaults (`receive_timeout: 15_000`) < `:req_options` < per-call options. `method`, `url` and the Authorization header are always set by the library; extra `:headers` are appended.

Define your mailer module:

```elixir
defmodule MyApp.Mailer do
  use Swoosh.Mailer, otp_app: :my_app
end
```

## Usage

```elixir
import Swoosh.Email

new()
|> to({"Alice", "alice@example.com"})
|> from({"My App", "noreply@yourdomain.com"})
|> subject("Welcome!")
|> html_body("<h1>Hello, Alice!</h1>")
|> MyApp.Mailer.deliver()
```

### Sending many emails

`MyApp.Mailer.deliver_many/1` sends concurrently and returns `{:ok, results}` with one result per email, in input order. Set `:max_concurrency` in the mailer config (default `System.schedulers_online()`) to limit parallelism. Each task times out after the effective `receive_timeout` (from `:req_options`, default 15 000 ms) plus 5 000 ms, giving `{:error, :timeout}`. A timeout result is ambiguous: the email may have been sent.

### Provider options

Values set with `Swoosh.Email.put_provider_option/3` are merged into the JSON payload (keys converted to strings) and override built fields. Use this as an escape hatch for API fields the adapter does not map yet:

```elixir
email |> Swoosh.Email.put_provider_option(:some_new_field, "value")
```

### Success response

`deliver/2` returns a map:

```elixir
{:ok, %{
  id: "message-id",
  delivered: ["alice@example.com"],
  permanent_bounces: [],
  queued: [],
  suppressed_recipients: []
}}
```

- `id` is the Cloudflare message ID, which you can trace in the Email Service activity log.
- `suppressed_recipients` lists recipients dropped because they are on the suppression list (only when "Drop suppressed recipients" is enabled on the sending domain).

## Headers and one-click unsubscribe

Custom headers are validated before any request. Headers controlled by Cloudflare (`Date`, `Message-ID`, `MIME-Version`, `Content-Type`, `Content-Transfer-Encoding`, `DKIM-Signature`, `Return-Path`, `Received`, `Feedback-ID`, `ARC-*`, `TLS-*`, `CFBL-*`) and headers with a dedicated API field (`From`, `To`, `Cc`, `Bcc`, `Subject`, `Reply-To`) are rejected, case-insensitively, without making a request:

```elixir
{:error, {:invalid_header, "Date", :not_allowed}}
{:error, {:invalid_header, "Subject", :use_api_field}}
{:error, {:invalid_header, "X-Foo", :invalid_value}}  # nil value
```

See the [Cloudflare header reference](https://developers.cloudflare.com/email-service/reference/headers/) for all rules. Non-string header values are converted with `to_string/1`.

Use `SwooshCloudflare.put_list_unsubscribe/3` for one-click unsubscribe (RFC 8058). The URL must be `https://`:

```elixir
email
|> SwooshCloudflare.put_list_unsubscribe("https://example.com/unsubscribe/abc",
  mailto: "unsubscribe@example.com"
)
# List-Unsubscribe: <https://example.com/unsubscribe/abc>, <mailto:unsubscribe@example.com>
# List-Unsubscribe-Post: List-Unsubscribe=One-Click
```

Pass `one_click: false` to skip the `List-Unsubscribe-Post` header.

## Inline images

Use `type: :inline` with a `cid`, and reference it from the HTML body:

```elixir
import Swoosh.Email

new()
|> to("alice@example.com")
|> from("noreply@yourdomain.com")
|> subject("Welcome!")
|> html_body(~s(<img src="cid:logo">))
|> attachment(Swoosh.Attachment.new("logo.png", type: :inline, cid: "logo"))
```

## Raw MIME messages

To send a MIME message you built yourself, use `SwooshCloudflare.send_raw/4`. It takes the message, the envelope sender, the envelope recipients and the mailer config, and returns the same values as `deliver/2`:

```elixir
config = Application.get_env(:my_app, MyApp.Mailer)

SwooshCloudflare.send_raw(mime_message, "noreply@yourdomain.com", ["alice@example.com"], config)
#=> {:ok, %{id: "message-id", delivered: ["alice@example.com"], ...}}
```

## Suppressions

`SwooshCloudflare.Suppressions` manages the suppression list. Every function takes the mailer config as its last argument, and suppressions are returned as decoded maps with string keys.

```elixir
alias SwooshCloudflare.Suppressions

config = Application.get_env(:my_app, MyApp.Mailer)

# List (cursor-based pagination)
{:ok, %{suppressions: list, next_cursor: cursor}} =
  Suppressions.list(config, reason: :hard_bounce, per_page: 100)

# Fetch the next page when next_cursor is not nil
{:ok, page2} = Suppressions.list(config, cursor: cursor)

# Create, optionally scoped to a sending domain and/or temporary
{:ok, suppression} =
  Suppressions.create("bob@example.com", config,
    scope: {:sending_domain, "mail.example.com"},
    note: "asked to stop",
    expires_at: ~U[2030-01-01 00:00:00Z]
  )

# Get, update (expires_at: nil makes it permanent, note: "" clears it), delete
{:ok, _} = Suppressions.get(suppression["id"], config)
{:ok, _} = Suppressions.update(suppression["id"], config, expires_at: nil)
{:ok, _} = Suppressions.delete(suppression["id"], config)

# Bulk import (max 1000 items)
{:ok, _} = Suppressions.import([%{email: "a@example.com"}, %{email: "b@example.com"}], config)
```

## Sending subdomains

`SwooshCloudflare.Subdomains` manages the sending subdomains of a zone. They are zone-scoped, so every function takes the `zone_id` first; only `:api_token` is needed in the config. Subdomains are returned as decoded maps with string keys.

```elixir
alias SwooshCloudflare.Subdomains

zone_id = "023e105f4ecef8ad9ca31a8372d0c353"

{:ok, subdomains} = Subdomains.list(zone_id, config)
{:ok, sub} = Subdomains.create(zone_id, "send.example.com", config)
{:ok, _} = Subdomains.get(zone_id, sub["tag"], config)

# Only the given fields are sent: :drop_suppressed_recipients and :preview_enabled
{:ok, _} = Subdomains.update(zone_id, sub["tag"], config, drop_suppressed_recipients: true)

# DNS records to add so the subdomain can be verified
{:ok, records} = Subdomains.dns_records(zone_id, sub["tag"], config)

{:ok, _} = Subdomains.delete(zone_id, sub["tag"], config)
```

## Events and Queues

Cloudflare can publish Email Sending lifecycle events (`delivered`, `deferred`, `bounced`, `failed`, `rejected`, `complained`) to a [Queue](https://developers.cloudflare.com/email-service/reference/event-subscriptions/). Create an event subscription for your sending domain, enable [HTTP pull](https://developers.cloudflare.com/queues/configuration/pull-consumers/) on the queue, and consume it with `SwooshCloudflare.Queues`.

The API token needs the Queues read and write permissions ("Account > Queues > Edit"), because acknowledging a message writes to the queue. Config needs `:api_token` and `:account_id`.

```elixir
alias SwooshCloudflare.Queues

{:ok, messages} = Queues.pull(queue_id, config, batch_size: 50, visibility_timeout_ms: 30_000)

{done, failed} =
  Enum.split_with(messages, fn message ->
    case message.event do
      %SwooshCloudflare.Event{type: :bounced} = event ->
        MyApp.Mailing.mark_bounced(event.recipient, event.bounce) == :ok

      _ ->
        true
    end
  end)

# Acknowledge what you processed; retry the rest after 60 seconds
Queues.ack(queue_id, Enum.map(done, & &1.lease_id), config,
  retries: Enum.map(failed, &{&1.lease_id, 60})
)
```

Each message is `%{id, lease_id, attempts, timestamp_ms, body, event}`. `event` is a `SwooshCloudflare.Event` (or `nil` when the body is not an Email Sending event). `SwooshCloudflare.Event.parse/1` also accepts a decoded map or JSON string if you receive the events some other way. Queues uses short polling, so sleep between empty pulls; the library ships no consumer process, run the loop under your own supervised process (see `SwooshCloudflare.Queues` for a minimal example).

Whether an event's `message_id` matches the id returned by `deliver/2` is not documented by Cloudflare and has not been verified, see `SwooshCloudflare.Event`.

## Analytics

`SwooshCloudflare.Analytics` queries the [GraphQL Analytics API](https://developers.cloudflare.com/analytics/graphql-api/). The API token needs the **Analytics Read** permission, and only `:api_token` is needed in the config. Email Service datasets are zone-level and retained for 31 days.

```elixir
alias SwooshCloudflare.Analytics

{:ok, data} =
  Analytics.query(
    """
    query($zoneTag: string!, $start: Date!, $end: Date!) {
      viewer {
        zones(filter: {zoneTag: $zoneTag}) {
          emailSendingAdaptiveGroups(filter: {date_geq: $start, date_leq: $end}, limit: 100) {
            count
            dimensions { date status }
          }
        }
      }
    }
    """,
    %{"zoneTag" => zone_id, "start" => "2026-06-01", "end" => "2026-06-07"},
    config
  )

# Individual delivery events of one message (last 24 hours by default)
{:ok, rows} = Analytics.message_events(zone_id, message_id, config, limit: 20)
```

GraphQL `errors` in a successful HTTP response are returned as `{:error, {200, :graphql_error, errors}}`. Filtering `message_events/4` by `messageId` is not shown in Cloudflare's documentation and is unverified.

## Error handling

`deliver/2`, `send_raw/4` and the `Suppressions`, `Subdomains`, `Queues` and `Analytics` functions return `{:error, {http_status, reason, body}}` on most errors, where `body` is Cloudflare's response body (decoded JSON, or the raw text for non-JSON responses) so the original message is never lost.

For **429 rate limiting**, the third element is the `Retry-After` value in seconds (or `nil` if the header was absent):

```elixir
{:error, {429, :rate_limited, 60}}
```

Any 2xx with a JSON body is a success. A 2xx without one returns `{:error, {status, :invalid_response, body}}`.

Full error table ([Cloudflare docs](https://developers.cloudflare.com/email-service/api/send-emails/rest-api/#error-responses)):

| Reason | HTTP | Cloudflare code |
|---|---|---|
| `:invalid_request` | 400 | 10001 |
| `:message_too_large` | 400 | 10200 |
| `:no_content_length` | 400 | 10201 |
| `:invalid_email` | 400 | 10202 |
| `:authentication_error` | 401 | 10101, 10103 |
| `:forbidden` | 403 | 10102, 10105 |
| `:sending_disabled` | 403 | 10203 |
| `:account_suspended` | 403 | 10207 |
| `:not_found` | 404 | 10000 |
| `:rate_limited` | 429 | 10004 |
| `:server_error` | 500/503 | 10002, 10003, 10100 |
| `:unknown_error` | any | — |

When the response body has no usable Cloudflare error code (for example a non-JSON body from a proxy, or an unknown code), the reason falls back on the HTTP status: 401 `:authentication_error`, 403 `:forbidden`, 404 `:not_found`, 429 `:rate_limited`, 5xx `:server_error`, anything else `:unknown_error`. A known Cloudflare code always takes precedence over the status.

If you receive `:authentication_error`, verify that:
- The API token has the **Email Sending — Send** permission
- The token is scoped to the correct account

## Limitations

- **25 MiB max** total message size, including attachments.
- **50 recipients max** per email (combined to/cc/bcc).
- **Subject**: 998 characters max.
- **Custom headers**: 16 KB max combined.
- **Recipients**: before onboarding a sending domain you can only send to verified destination addresses; after onboarding a sending domain you can send to any recipient.
- **Domain requirement**: the `from` address must be on an onboarded sending domain.
- **Transactional only**: Bulk/marketing sending is not supported.

## Telemetry

Telemetry works out of the box via `Swoosh.Mailer` — no extra configuration needed. The following events are emitted automatically:

- `[:swoosh, :deliver, :start | :stop | :exception]`
- `[:swoosh, :deliver_many, :start | :stop | :exception]`

In addition, this library emits a span around every HTTP request it makes (adapter, `send_raw/4`, `Suppressions`, `Subdomains`, `Queues` and `Analytics`):

- `[:swoosh_cloudflare, :request, :start]` with metadata `%{method: :post, path: "/send"}`
- `[:swoosh_cloudflare, :request, :stop]` with `%{duration: native_time}` measurements and metadata `%{method: atom, path: String.t(), status: integer | nil, result: :ok | :error}`. `status` is `nil` on transport errors.
- `[:swoosh_cloudflare, :request, :exception]` if the request raises.

For the adapter, `send_raw/4` and `Suppressions`, `path` is relative to `/accounts/{account_id}/email/sending`; for `Subdomains`, `Queues` and `Analytics` it is the full path after the base URL (for example `/graphql`). The API token and the payload are never included in the metadata.

```elixir
:telemetry.attach(
  "log-cloudflare-requests",
  [:swoosh_cloudflare, :request, :stop],
  fn _event, %{duration: d}, meta, _ ->
    ms = System.convert_time_unit(d, :native, :millisecond)
    Logger.info("cloudflare #{meta.method} #{meta.path} -> #{inspect(meta.status)} (#{ms}ms)")
  end,
  nil
)
```

See the [Swoosh telemetry documentation](https://hexdocs.pm/swoosh/Swoosh.Mailer.html#module-telemetry) for details on attaching handlers.

## Resources

- [Cloudflare Email Service documentation](https://developers.cloudflare.com/email-service/)
- [Send emails guide](https://developers.cloudflare.com/email-service/get-started/send-emails/)
- [API limits](https://developers.cloudflare.com/email-service/platform/limits/)
- [Swoosh documentation](https://hexdocs.pm/swoosh)

## License

MIT
