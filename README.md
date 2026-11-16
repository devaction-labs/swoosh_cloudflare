# SwooshCloudflare

[Swoosh](https://github.com/swoosh/swoosh) adapter for [Cloudflare Email Service](https://developers.cloudflare.com/email-service/).

> **Note:** Cloudflare Email Service is currently in **beta**. The API may change before general availability. Check the [official documentation](https://developers.cloudflare.com/email-service/) for the latest updates.

## Installation

```elixir
def deps do
  [
    {:swoosh_cloudflare, "~> 0.3"}
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

```elixir
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Cloudflare,
  api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")
```

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

### Success response

`deliver/2` returns a map with three fields:

```elixir
{:ok, %{
  delivered: ["alice@example.com"],
  permanent_bounces: [],
  queued: []
}}
```

## Error handling

`deliver/2` returns `{:error, {http_status, reason, body}}` on most errors, where `body` is Cloudflare's response body (decoded JSON, or the raw text for non-JSON responses) so the original message is never lost.

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

If you receive `:authentication_error`, verify that:
- The API token has the **Email Sending — Send** permission
- The token is scoped to the correct account

## Limitations

- **Verified addresses only**: New accounts can only send to addresses verified in your Cloudflare dashboard. Paid plans unlock general sending.
- **Domain requirement**: The `from` address must belong to a domain with [Email Routing](https://developers.cloudflare.com/email-routing/) active in your Cloudflare account.
- **50 recipients max** per email (combined to/cc/bcc).
- **5 MiB max** total message size (25 MiB for verified accounts).
- **Transactional only**: Bulk/marketing sending is not supported.

## Telemetry

Telemetry works out of the box via `Swoosh.Mailer` — no extra configuration needed. The following events are emitted automatically:

- `[:swoosh, :deliver, :start | :stop | :exception]`
- `[:swoosh, :deliver_many, :start | :stop | :exception]`

See the [Swoosh telemetry documentation](https://hexdocs.pm/swoosh/Swoosh.Mailer.html#module-telemetry) for details on attaching handlers.

## Resources

- [Cloudflare Email Service documentation](https://developers.cloudflare.com/email-service/)
- [Send emails guide](https://developers.cloudflare.com/email-service/get-started/send-emails/)
- [API limits](https://developers.cloudflare.com/email-service/platform/limits/)
- [Swoosh documentation](https://hexdocs.pm/swoosh)

## License

MIT
