defmodule SwooshCloudflare.Client do
  @moduledoc false

  alias SwooshCloudflare.Error

  @base_url "https://api.cloudflare.com/client/v4"

  def send(payload, config) do
    base = Keyword.get(config, :base_url, @base_url)
    url = "#{base}/accounts/#{config[:account_id]}/email/sending/send"

    case Req.post(url, json: payload, headers: headers(config), receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{id: get_in(body, ["result", "delivered"]) || []}}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.from_response(status, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers(config) do
    [{"Authorization", "Bearer #{config[:api_token]}"}]
  end
end
