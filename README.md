# SwooshCloudflare

[Swoosh](https://github.com/swoosh/swoosh) adapter for [Cloudflare Email Service](https://developers.cloudflare.com/email-service/).

## Installation

```elixir
def deps do
  [
    {:swoosh_cloudflare, "~> 0.1"}
  ]
end
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

## Limitations

- **Verified addresses only**: New accounts can only send to addresses verified in your Cloudflare dashboard. Paid plans unlock general sending.
- **Domain requirement**: The `from` address must belong to a domain with [Email Routing](https://developers.cloudflare.com/email-routing/) active in your Cloudflare account.
- **50 recipients max** per email.
- **5 MiB max** total message size.

## Error handling

`deliver/1` returns `{:error, {http_status, reason}}` on API errors:

| Reason | HTTP | Cloudflare code |
|---|---|---|
| `:invalid_request` | 400 | 10001 |
| `:invalid_content` | 400 | 10200 |
| `:message_too_large` | 400 | 10202 |
| `:sending_disabled` | 403 | 10203 |
| `:rate_limited` | 429 | 10004 |
| `:server_error` | 500 | 10002 |
| `:unknown_error` | any | — |

## License

MIT
