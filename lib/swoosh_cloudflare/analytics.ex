defmodule SwooshCloudflare.Analytics do
  @moduledoc """
  Query Cloudflare's [GraphQL Analytics API](https://developers.cloudflare.com/analytics/graphql-api/),
  for example to inspect Email Sending delivery events.

  `config` is the same keyword list as the mailer's, but only `:api_token` is required
  (`:account_id` is not used; the Email Service datasets are zone-level, so you pass a
  zone id). `:base_url` and `:req_options` are honoured; the request goes to
  `{base_url}/graphql`.

  ## Required token permission

  The API token needs the **Analytics Read** permission. This is usually a different
  token from the one used to send email.

      config = Application.get_env(:my_app, MyApp.Mailer)

      {:ok, %{"viewer" => viewer}} =
        SwooshCloudflare.Analytics.query(
          \"\"\"
          query($zoneTag: string!, $start: Date!, $end: Date!) {
            viewer {
              zones(filter: {zoneTag: $zoneTag}) {
                emailSendingAdaptiveGroups(
                  filter: {date_geq: $start, date_leq: $end}
                  limit: 100
                ) {
                  count
                  dimensions { date status }
                }
              }
            }
          }
          \"\"\",
          %{"zoneTag" => zone_id, "start" => "2026-06-01", "end" => "2026-06-07"},
          config
        )

  Cloudflare retains Email Service analytics for the past 31 days.

  Errors use the same shapes as the mailer, plus
  `{:error, {status, :graphql_error, errors}}` when Cloudflare answers with a successful
  HTTP status but a non-empty GraphQL `errors` list.
  """

  alias SwooshCloudflare.Client

  @type config :: keyword()

  @fields ~w(datetime from to subject status eventType sendingDomain messageId
             errorCause errorDetail dkim dmarc spf isSpam)

  @events_query """
  query EmailSendingMessageEvents($zoneTag: string!, $messageId: string!, $start: Time!, $end: Time!, $limit: Int!) {
    viewer {
      zones(filter: { zoneTag: $zoneTag }) {
        emailSendingAdaptive(
          filter: { messageId: $messageId, datetime_geq: $start, datetime_leq: $end }
          limit: $limit
          orderBy: [datetime_DESC]
        ) {
          #{Enum.join(@fields, "\n        ")}
        }
      }
    }
  }
  """

  @doc """
  Runs a GraphQL query and returns its `data`.

  `variables` is a map (or `nil`) sent as the GraphQL variables. Returns
  `{:ok, data}`, or `{:error, {status, :graphql_error, errors}}` when the response carries
  GraphQL `errors`, even if the HTTP status was 200.
  """
  @spec query(String.t(), map() | nil, config()) :: {:ok, map() | nil} | {:error, term()}
  def query(query_string, variables, config) when is_binary(query_string) do
    payload = %{"query" => query_string, "variables" => variables || %{}}

    with {:ok, %{} = resp} <- Client.call(:post, "/graphql", config, json: payload) do
      case resp["errors"] do
        errors when errors in [nil, []] -> {:ok, resp["data"]}
        errors -> {:error, {200, :graphql_error, errors}}
      end
    end
  end

  @doc """
  Fetches the Email Sending events recorded for one message, newest first.

  Queries the `emailSendingAdaptive` dataset of the zone `zone_tag` and returns
  `{:ok, rows}`, where each row is a map with string keys: `"datetime"`, `"from"`, `"to"`,
  `"subject"`, `"status"`, `"eventType"`, `"sendingDomain"`, `"messageId"`, `"errorCause"`,
  `"errorDetail"`, `"dkim"`, `"dmarc"`, `"spf"` and `"isSpam"`.

  Options:

    * `:start` - a `DateTime`, start of the window (default: 24 hours ago).
    * `:end` - a `DateTime`, end of the window (default: now).
    * `:limit` - maximum number of rows (default: 100).

  Cloudflare only retains 31 days of data. The dataset, its fields and the
  `datetime_geq`/`datetime_leq` filters come from the Cloudflare documentation, but
  filtering on `messageId` is **UNVERIFIED**: the documentation lists `messageId` as a
  field of the dataset without showing it used as a filter. If Cloudflare rejects it you
  get a `:graphql_error`. Whether `messageId` here equals the `message_id` returned by
  `/send` is also unverified (see `SwooshCloudflare.Event`).
  """
  @spec message_events(String.t(), String.t(), config(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def message_events(zone_tag, message_id, config, opts \\ []) do
    now = DateTime.utc_now()

    variables = %{
      "zoneTag" => zone_tag,
      "messageId" => message_id,
      "start" => opts |> Keyword.get_lazy(:start, fn -> DateTime.add(now, -86_400) end) |> iso(),
      "end" => opts |> Keyword.get(:end, now) |> iso(),
      "limit" => Keyword.get(opts, :limit, 100)
    }

    with {:ok, data} <- query(@events_query, variables, config) do
      {:ok, rows(data)}
    end
  end

  defp rows(%{"viewer" => %{"zones" => [%{"emailSendingAdaptive" => rows} | _]}})
       when is_list(rows),
       do: rows

  defp rows(_), do: []

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(value) when is_binary(value), do: value
end
