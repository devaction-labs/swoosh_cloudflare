defmodule SwooshCloudflare.Error do
  @moduledoc false

  @spec from_response(non_neg_integer(), term()) :: {non_neg_integer(), atom()}
  def from_response(status, body) when is_map(body) do
    code = get_in(body, ["errors", Access.at(0), "code"])
    {status, map_code(code)}
  end

  def from_response(status, _body), do: {status, :unknown_error}

  defp map_code(10000), do: :authentication_error
  defp map_code(10001), do: :invalid_request
  defp map_code(10200), do: :invalid_content
  defp map_code(10202), do: :message_too_large
  defp map_code(10203), do: :sending_disabled
  defp map_code(10004), do: :rate_limited
  defp map_code(10002), do: :server_error
  defp map_code(_), do: :unknown_error
end
