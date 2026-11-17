defmodule SwooshCloudflare.Queues do
  @moduledoc """
  HTTP pull consumer for Cloudflare Queues, to receive Email Sending lifecycle events.

  Configure an
  [event subscription](https://developers.cloudflare.com/email-service/reference/event-subscriptions/)
  that publishes to a queue, enable
  [HTTP pull](https://developers.cloudflare.com/queues/configuration/pull-consumers/) on that
  queue, then `pull/3` batches of messages and `ack/4` them once processed.

  `config` is the same keyword list as the mailer's; `:api_token` and `:account_id` are
  required, `:base_url` and `:req_options` are honoured.

  ## Required token permissions

  An HTTP pull consumer mutates queue state, so the API token needs both Queues read and
  write (`com.cloudflare.api.account.queues_read` and
  `com.cloudflare.api.account.queues_write`, "Account > Queues > Edit" in the dashboard).
  This is usually a different token from the one used to send email.

  ## Polling example

  Cloudflare Queues uses short polling: an empty queue returns an empty list immediately,
  so sleep between empty pulls. This library ships no process for it; run the loop under
  your own supervised `Task` or `GenServer`.

      defmodule MyApp.EmailEvents do
        alias SwooshCloudflare.Queues

        def run(queue_id, config) do
          case Queues.pull(queue_id, config, batch_size: 50, visibility_timeout_ms: 30_000) do
            {:ok, []} ->
              Process.sleep(5_000)

            {:ok, messages} ->
              {done, failed} = Enum.split_with(messages, &handle(&1.event))
              Queues.ack(queue_id, Enum.map(done, & &1.lease_id), config,
                retries: Enum.map(failed, &{&1.lease_id, 60}))

            {:error, _reason} ->
              Process.sleep(30_000)
          end

          run(queue_id, config)
        end

        # Return true to acknowledge, false to retry later.
        defp handle(%SwooshCloudflare.Event{type: :bounced} = event), do: record(event)
        defp handle(_event), do: true
      end

  Messages that are neither acknowledged nor retried become available again once the
  visibility timeout expires, so handlers must be idempotent. Use `:event_id` of
  `SwooshCloudflare.Event` to deduplicate.

  Errors use the same shapes as the mailer: `{:error, {status, reason, body}}`,
  `{:error, {429, :rate_limited, retry_after}}`, or a network error term.
  """

  alias SwooshCloudflare.Client
  alias SwooshCloudflare.Event

  @type config :: keyword()
  @type message :: %{
          id: String.t() | nil,
          lease_id: String.t() | nil,
          attempts: number() | nil,
          timestamp_ms: number() | nil,
          body: term(),
          event: Event.t() | nil
        }

  @doc """
  Pulls a batch of messages from the queue.

  Options (only given ones are sent): `:batch_size` (Cloudflare default 5, maximum 100) and
  `:visibility_timeout_ms` (how long the messages are leased to you; Cloudflare default
  30 seconds, maximum 12 hours).

  Returns `{:ok, messages}`, an empty list when the queue has nothing to deliver. Each
  message is a map with:

    * `:id`, `:lease_id`, `:attempts`, `:timestamp_ms` - as returned by Cloudflare. Hold on
      to `:lease_id`: it is what you pass to `ack/4`.
    * `:body` - the message body, decoded (see below).
    * `:event` - the body parsed with `SwooshCloudflare.Event.parse/1`, or `nil` when the
      body is not an Email Sending event.

  ## Body decoding

  Cloudflare returns `body` as a string and reports how the message was published in
  `metadata["CF-Content-Type"]`. The Cloudflare documentation says `json` and `bytes`
  bodies are base64-encoded for pull consumers and `text` is plain UTF-8, but its own
  example shows a `json` body that is not base64. Because of that, decoding is lenient:

    * `"text"` - the body is returned as is.
    * `"bytes"` - base64-decoded to a binary (as is if it is not valid base64).
    * `"json"`, or no content type - parsed as JSON; if that fails, base64-decoded and
      parsed as JSON; if that also fails, returned as is.

  How event subscription messages are encoded in practice is **UNVERIFIED**: the leniency
  above exists so that both plain and base64-wrapped JSON yield the decoded event map.
  """
  @spec pull(String.t(), config(), keyword()) :: {:ok, [message()]} | {:error, term()}
  def pull(queue_id, config, opts \\ []) do
    body =
      for key <- [:batch_size, :visibility_timeout_ms],
          Keyword.get(opts, key) != nil,
          into: %{},
          do: {Atom.to_string(key), Keyword.fetch!(opts, key)}

    with {:ok, resp} <- Client.call(:post, path(queue_id, config, "pull"), config, json: body) do
      messages =
        case resp["result"] do
          %{"messages" => list} when is_list(list) -> list
          _ -> []
        end

      {:ok, Enum.map(messages, &build_message/1)}
    end
  end

  @doc """
  Acknowledges pulled messages by `lease_id`, and optionally marks others for retry.

  `lease_ids` is the list of leases to acknowledge. Options:

    * `:retries` - a list of `lease_id` or `{lease_id, delay_seconds}` to put back in the
      queue, optionally delaying their next delivery by `delay_seconds`.

  Returns `{:ok, %{ack_count: n, retry_count: n, warnings: map}}`.
  """
  @spec ack(String.t(), [String.t()], config(), keyword()) ::
          {:ok, %{ack_count: number(), retry_count: number(), warnings: map()}}
          | {:error, term()}
  def ack(queue_id, lease_ids, config, opts \\ []) when is_list(lease_ids) do
    body = %{
      "acks" => Enum.map(lease_ids, &%{"lease_id" => &1}),
      "retries" => opts |> Keyword.get(:retries, []) |> Enum.map(&retry_item/1)
    }

    with {:ok, resp} <- Client.call(:post, path(queue_id, config, "ack"), config, json: body) do
      result = if is_map(resp["result"]), do: resp["result"], else: %{}

      {:ok,
       %{
         ack_count: result["ackCount"] || 0,
         retry_count: result["retryCount"] || 0,
         warnings: result["warnings"] || %{}
       }}
    end
  end

  defp retry_item({lease_id, delay_seconds}),
    do: %{"lease_id" => lease_id, "delay_seconds" => delay_seconds}

  defp retry_item(lease_id) when is_binary(lease_id), do: %{"lease_id" => lease_id}

  defp build_message(raw) when is_map(raw) do
    body = decode_body(raw["body"], content_type(raw["metadata"]))

    event =
      case Event.parse(body) do
        {:ok, %Event{raw_type: "cf.email.sending." <> _} = event} -> event
        _ -> nil
      end

    %{
      id: raw["id"],
      lease_id: raw["lease_id"],
      attempts: raw["attempts"],
      timestamp_ms: raw["timestamp_ms"],
      body: body,
      event: event
    }
  end

  defp content_type(%{"CF-Content-Type" => type}) when is_binary(type), do: type
  defp content_type(_), do: nil

  defp decode_body(body, "text"), do: body

  defp decode_body(body, "bytes") when is_binary(body) do
    case Base.decode64(body, padding: false, ignore: :whitespace) do
      {:ok, bytes} -> bytes
      :error -> body
    end
  end

  defp decode_body(body, _json_or_unknown) when is_binary(body) do
    with {:error, _} <- Jason.decode(body),
         {:ok, bytes} <- Base.decode64(body, padding: false, ignore: :whitespace),
         {:ok, decoded} <- Jason.decode(bytes) do
      decoded
    else
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp decode_body(body, _), do: body

  defp path(queue_id, config, action) do
    "/accounts/#{encode(config[:account_id])}/queues/#{encode(queue_id)}/messages/#{action}"
  end

  defp encode(id), do: URI.encode(to_string(id), &URI.char_unreserved?/1)
end
