defmodule SwooshCloudflare.Client do
  @moduledoc false

  alias SwooshCloudflare.Error

  @base_url "https://api.cloudflare.com/client/v4"

  @spec send(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def send(payload, config) do
    base = Keyword.get(config, :base_url, @base_url)
    url = "#{base}/accounts/#{config[:account_id]}/email/sending/send"

    case Req.post(url, json: payload, headers: headers(config), receive_timeout: 15_000) do
      {:ok, %{status: status, body: %{} = body}} when status in 200..299 ->
        result = if is_map(body["result"]), do: body["result"], else: %{}

        {:ok,
         %{
           delivered: result["delivered"] || [],
           permanent_bounces: result["permanent_bounces"] || [],
           queued: result["queued"] || []
         }}

      # A 2xx that is not JSON: the mail may or may not have gone, so it is an error, not a raise.
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:error, {status, :invalid_response, body}}

      {:ok, %{status: 429, headers: resp_headers}} ->
        retry_after =
          resp_headers
          |> Map.get("retry-after", [])
          |> List.first()
          |> parse_retry_after()

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
