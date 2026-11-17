defmodule SwooshCloudflare.Client do
  @moduledoc false

  alias SwooshCloudflare.Error

  @base_url "https://api.cloudflare.com/client/v4"
  @default_receive_timeout 15_000

  @spec send(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def send(payload, config), do: send_request("/send", payload, config)

  @spec send_raw(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def send_raw(payload, config), do: send_request("/send_raw", payload, config)

  defp send_request(path, payload, config) do
    with {:ok, body} <- request(:post, path, config, json: payload) do
      result = if is_map(body["result"]), do: body["result"], else: %{}

      {:ok,
       %{
         id: result["message_id"],
         delivered: result["delivered"] || [],
         permanent_bounces: result["permanent_bounces"] || [],
         queued: result["queued"] || [],
         suppressed_recipients: result["suppressed_recipients"] || []
       }}
    end
  end

  # Performs a request against `{base}/accounts/{account_id}/email/sending{path}`.
  # Returns the decoded JSON envelope on 2xx, or the shared error tuples.
  # `req_opts` may carry `:json` and `:params`.
  @spec request(atom(), String.t(), keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(method, path, config, req_opts \\ []) do
    for key <- [:api_token, :account_id], is_nil(config[key]) do
      raise ArgumentError, "expected #{inspect(key)} to be set in the config"
    end

    base = Keyword.get(config, :base_url, @base_url)
    url = "#{base}/accounts/#{config[:account_id]}/email/sending#{path}"

    req_opts = build_req_opts(method, url, config, req_opts)

    case Req.request(req_opts) do
      {:ok, %{status: status, body: %{} = body}} when status in 200..299 ->
        {:ok, body}

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

  # Precedence: library defaults < config `:req_options` < per-call options.
  # `method`, `url` and the Authorization header are always set by the library.
  defp build_req_opts(method, url, config, call_opts) do
    user_opts = Keyword.get(config, :req_options, [])

    [receive_timeout: @default_receive_timeout]
    |> Keyword.merge(Keyword.drop(user_opts, [:method, :url, :headers]))
    |> Keyword.merge(call_opts)
    |> Keyword.merge(
      method: method,
      url: url,
      headers: headers(config, Keyword.get(user_opts, :headers, []))
    )
  end

  defp headers(config, extra) do
    extra =
      extra
      |> Enum.to_list()
      |> Enum.reject(fn {name, _} ->
        name |> to_string() |> String.downcase() == "authorization"
      end)

    [{"Authorization", "Bearer #{config[:api_token]}"} | extra]
  end

  defp parse_retry_after(nil), do: nil

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end
end
