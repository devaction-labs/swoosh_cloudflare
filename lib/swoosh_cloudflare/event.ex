defmodule SwooshCloudflare.Event do
  @moduledoc """
  A Cloudflare Email Sending lifecycle event, as published to a Cloudflare Queue by an
  [event subscription](https://developers.cloudflare.com/email-service/reference/event-subscriptions/).

  Use `parse/1` on the decoded message body (a map) or on the raw JSON string:

      {:ok, %SwooshCloudflare.Event{type: :bounced, recipient: "user@example.net"}} =
        SwooshCloudflare.Event.parse(json_or_map)

  Use `SwooshCloudflare.Queues.pull/3` to receive these events over HTTP.

  ## Fields

    * `:type` - one of `:delivered`, `:deferred`, `:bounced`, `:failed`, `:rejected`,
      `:complained`, or `:unknown` for an event type this library does not know.
    * `:raw_type` - the type string as received (for example
      `"cf.email.sending.message.delivered"`).
    * `:event_id`, `:message_id`, `:sender`, `:recipient`, `:subject`, `:terminal` -
      from `payload` (`eventId`, `messageId`, ...). `:subject` is absent for some events.
    * `:delivery`, `:bounce`, `:failure`, `:rejection`, `:complaint` - the corresponding
      `payload` sub-maps with their original string keys (for example
      `%{"status" => "bounced", "smtpStatusCode" => "550"}`), or `nil` when absent.
    * `:metadata` - the `metadata` map (`accountId`, `eventSubscriptionId`,
      `eventSchemaVersion`, `eventTimestamp`) and `:source` - the `source` map
      (`type`, `zoneId`, `domain`).
    * `:timestamp` - `metadata.eventTimestamp` as a `DateTime`, or `nil`.
    * `:raw` - the full decoded map, so fields this library does not model are not lost.

  ## Correlating an event with a sent email

  Events carry `payload.messageId` (for example `"0101018f7d0c4d9a-msg-deadbeef"`).
  The Cloudflare documentation does not say whether this value equals the `message_id`
  returned by the `/send` endpoint (the Swoosh `:id` in the delivery result), nor whether
  it is wrapped in angle brackets like an RFC 5322 `Message-ID`. This is **UNVERIFIED**:
  the REST API documentation shows no `message_id` in the `/send` response, and the
  documented event examples use bare values without brackets. Compare a real `/send`
  result with a real event before relying on it, and consider stripping `<` and `>`
  from both sides when matching.
  """

  @enforce_keys [:type, :raw_type, :raw]
  defstruct [
    :type,
    :raw_type,
    :event_id,
    :message_id,
    :sender,
    :recipient,
    :subject,
    :terminal,
    :delivery,
    :bounce,
    :failure,
    :rejection,
    :complaint,
    :metadata,
    :source,
    :timestamp,
    :raw
  ]

  @type event_type :: :delivered | :deferred | :bounced | :failed | :rejected | :complained
  @type t :: %__MODULE__{
          type: event_type() | :unknown,
          raw_type: String.t(),
          event_id: String.t() | nil,
          message_id: String.t() | nil,
          sender: String.t() | nil,
          recipient: String.t() | nil,
          subject: String.t() | nil,
          terminal: boolean() | nil,
          delivery: map() | nil,
          bounce: map() | nil,
          failure: map() | nil,
          rejection: map() | nil,
          complaint: map() | nil,
          metadata: map() | nil,
          source: map() | nil,
          timestamp: DateTime.t() | nil,
          raw: map()
        }

  @types %{
    "cf.email.sending.message.delivered" => :delivered,
    "cf.email.sending.message.deferred" => :deferred,
    "cf.email.sending.message.bounced" => :bounced,
    "cf.email.sending.message.failed" => :failed,
    "cf.email.sending.message.rejected" => :rejected,
    "cf.email.sending.message.complained" => :complained
  }

  @doc """
  Parses a decoded event map or a JSON string into an `Event`.

  Returns `{:error, :invalid_json}` for a string that is not valid JSON and
  `{:error, :invalid_event}` for anything that does not have the event envelope
  (a `"type"` string and a `"payload"` map). Never raises.
  """
  @spec parse(map() | binary()) :: {:ok, t()} | {:error, :invalid_json | :invalid_event}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} -> parse(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse(%{"type" => type, "payload" => %{} = payload} = map) when is_binary(type) do
    {:ok,
     %__MODULE__{
       type: Map.get(@types, type, :unknown),
       raw_type: type,
       event_id: payload["eventId"],
       message_id: payload["messageId"],
       sender: payload["sender"],
       recipient: payload["recipient"],
       subject: payload["subject"],
       terminal: payload["terminal"],
       delivery: map_or_nil(payload["delivery"]),
       bounce: map_or_nil(payload["bounce"]),
       failure: map_or_nil(payload["failure"]),
       rejection: map_or_nil(payload["rejection"]),
       complaint: map_or_nil(payload["complaint"]),
       metadata: map_or_nil(map["metadata"]),
       source: map_or_nil(map["source"]),
       timestamp: timestamp(map["metadata"]),
       raw: map
     }}
  end

  def parse(_), do: {:error, :invalid_event}

  defp map_or_nil(%{} = value), do: value
  defp map_or_nil(_), do: nil

  defp timestamp(%{"eventTimestamp" => ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end

  defp timestamp(_), do: nil
end
