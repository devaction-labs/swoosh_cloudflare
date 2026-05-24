defmodule SwooshCloudflare.Client do
  @moduledoc false

  alias SwooshCloudflare.Error

  @base_url "https://api.cloudflare.com/client/v4"

  @spec send(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def send(payload, config) do
    base = Keyword.get(config, :base_url, @base_url)
    url = "#{base}/accounts/#{config[:account_id]}/email/sending/send"

    case Req.post(url, json: payload, headers: headers(config), receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        result = body["result"] || %{}

        {:ok,
         %{
           delivered: result["delivered"] || [],
           permanent_bounces: result["permanent_bounces"] || [],
           queued: result["queued"] || []
         }}

      {:ok, %{status: 429, body: body, headers: resp_headers}} ->
        retry_after =
          resp_headers
          |> Map.get("retry-after", [])
          |> List.first()
          |> parse_retry_after()

        _ = Error.from_response(429, body)
        {:error, {429, :rate_limited, retry_after}}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers(config) do
    [{"Authorization", "Bearer #{config[:api_token]}"}]
  end

  defp parse_retry_after(nil), do: nil

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end
end
