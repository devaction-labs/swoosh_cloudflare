defmodule SwooshCloudflare.Error do
  @moduledoc false

  # Codes from https://developers.cloudflare.com/email-service/api/send-emails/rest-api/#error-responses

  @spec from_response(non_neg_integer(), term()) :: {non_neg_integer(), atom(), term()}
  def from_response(status, body), do: {status, map_code(code(body)), body}

  # Never raises: a body without an `errors` list (HTML from a proxy, a plain string) has no code.
  defp code(%{"errors" => [%{"code" => code} | _]}), do: code
  defp code(_), do: nil

  defp map_code(10001), do: :invalid_request
  defp map_code(10200), do: :message_too_large
  defp map_code(10201), do: :no_content_length
  defp map_code(10202), do: :invalid_email
  defp map_code(code) when code in [10101, 10103], do: :authentication_error
  defp map_code(code) when code in [10102, 10105], do: :forbidden
  defp map_code(10203), do: :sending_disabled
  defp map_code(10207), do: :account_suspended
  defp map_code(10000), do: :not_found
  defp map_code(10004), do: :rate_limited
  defp map_code(code) when code in [10002, 10003, 10100], do: :server_error
  defp map_code(_), do: :unknown_error
end
