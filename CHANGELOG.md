# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2026-11-17

### Fixed

- `SwooshCloudflare.Queues.pull/3` sets `:event` only for Email Sending envelopes (`cf.email.sending.*`); other queue messages get `nil`.
- README: the Queues example now builds the acknowledged and retried lease ids it uses.

## [0.7.0] - 2026-11-17

### Added

- `SwooshCloudflare.Subdomains` to list, get, create, update and delete sending subdomains and to fetch their DNS records. (#21)
- `SwooshCloudflare.Event`, a struct and `parse/1` for Email Sending lifecycle events. (#20)
- `SwooshCloudflare.Queues`, an HTTP pull consumer (`pull/3`, `ack/4`) for receiving those events from a Cloudflare Queue. (#20)
- `SwooshCloudflare.Analytics` with `query/3` for the GraphQL Analytics API and `message_events/4` to look up the events of one message. GraphQL `errors` are returned as `{:error, {status, :graphql_error, errors}}`. (#22)

### Changed

- The internal HTTP client can now call any path under `:base_url`, not only `/accounts/{account_id}/email/sending`. Existing behavior, error shapes and telemetry are unchanged. The new modules report the full path after the base URL in the `[:swoosh_cloudflare, :request]` telemetry metadata.

## [0.6.0] - 2026-11-17

### Changed

- Minimum Elixir is now 1.16, matching Swoosh.

### Added

- `:req_options` config, merged into the `Req` options of every request (proxy, Finch pool, `retry`, timeouts, `Req.Test` plugs). Precedence is library defaults < `:req_options` < per-call options. (#15)
- `Swoosh.Email.provider_options` are merged into the JSON payload as an escape hatch for API fields the adapter does not map yet. (#15)
- Validation of custom headers before any request: platform-controlled headers and headers that have a dedicated API field are rejected with `{:error, {:invalid_header, name, reason}}`. (#16)
- `SwooshCloudflare.put_list_unsubscribe/3` for one-click unsubscribe headers. (#16)
- Telemetry span `[:swoosh_cloudflare, :request, :start | :stop | :exception]` around every HTTP request. `telemetry` is now a direct dependency. (#17)
- `:max_concurrency` config for `deliver_many/2`. (#18)
- Public types `t:Swoosh.Adapters.Cloudflare.send_result/0` and `t:Swoosh.Adapters.Cloudflare.error/0`. (#19)
- `LICENSE`, `CHANGELOG.md`, CI workflow, Credo and Dialyxir. (#19)

### Changed

- `deliver_many/2` task timeout is now the effective `receive_timeout` plus 5 seconds, instead of a fixed 30 seconds. (#18)

## [0.5.1] - 2026-11-17

### Fixed

- Raise `Swoosh.AttachmentContentError` for attachments without content.
- Fall back on the HTTP status when the error code is unknown.
- Inline attachments fall back to the filename as `content_id`, and attachment content is read through Swoosh.
- Accept a list of addresses in `reply_to`.
- `deliver_many/2` returns `{:ok, results}`.

### Documentation

- Document `api_client: false` and `runtime.exs` configuration.

## [0.5.0] - 2026-11-16

### Added

- `SwooshCloudflare.send_raw/4` to send pre-built MIME messages. (#7)
- `SwooshCloudflare.Suppressions` module to manage the suppression list. (#6)

### Changed

- Share request handling between the adapter, `send_raw/4` and `Suppressions` in a single client.

### Removed

- Placeholder `hello/0` function.

## [0.4.0] - 2026-11-16

### Added

- Send message ID and `suppressed_recipients` in the success result. (#3)
- Send named addresses as `{address, name}` objects. (#4)

### Fixed

- Send `content_id` for inline attachments. (#2)

### Documentation

- Update limits and examples. (#5)

## [0.3.1] - 2026-11-16

### Changed

- Dependency and version bump only.

## [0.3.0] - 2026-11-16

### Changed

- Map error codes per Cloudflare's documentation, keep the response body in error tuples and never raise on HTTP errors. (#1)

### Fixed

- Correct attachment fields to match the REST API spec.

### Documentation

- Clarify that telemetry works out of the box via `Swoosh.Mailer`.

[0.6.0]: https://github.com/devaction-labs/swoosh_cloudflare/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/devaction-labs/swoosh_cloudflare/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/devaction-labs/swoosh_cloudflare/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/devaction-labs/swoosh_cloudflare/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/devaction-labs/swoosh_cloudflare/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/devaction-labs/swoosh_cloudflare/releases/tag/v0.3.0
