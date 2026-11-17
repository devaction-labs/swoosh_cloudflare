defmodule SwooshCloudflare.Headers do
  @moduledoc false

  # Denylist based on
  # https://developers.cloudflare.com/email-service/reference/headers/
  # Matching is case-insensitive.

  @platform_controlled ~w(
    date message-id mime-version content-type content-transfer-encoding
    dkim-signature return-path received feedback-id
    tls-required tls-report-domain tls-report-submitter
    cfbl-address cfbl-feedback-id
  )

  @platform_prefixes ["arc-", "cfbl-"]

  @api_fields ~w(from to cc bcc subject reply-to)

  @type reason :: :use_api_field | :not_allowed | :invalid_value

  @doc """
  Validates and normalizes custom headers.

  Returns `{:ok, headers}` with every name and value as a string, or
  `{:error, {:invalid_header, name, reason}}` for the first offending header.
  """
  @spec validate(map() | nil) ::
          {:ok, %{String.t() => String.t()}} | {:error, {:invalid_header, String.t(), reason()}}
  def validate(nil), do: {:ok, %{}}

  def validate(headers) when is_map(headers) do
    headers
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.reduce_while({:ok, %{}}, fn {name, value}, {:ok, acc} ->
      name = to_string(name)

      case check(name, value) do
        {:ok, string} -> {:cont, {:ok, Map.put(acc, name, string)}}
        {:error, reason} -> {:halt, {:error, {:invalid_header, name, reason}}}
      end
    end)
  end

  def validate(_other), do: {:error, {:invalid_header, "headers", :invalid_value}}

  defp check(name, value) do
    lower = String.downcase(name)

    cond do
      lower in @api_fields -> {:error, :use_api_field}
      lower in @platform_controlled -> {:error, :not_allowed}
      Enum.any?(@platform_prefixes, &String.starts_with?(lower, &1)) -> {:error, :not_allowed}
      true -> stringify(value)
    end
  end

  defp stringify(nil), do: {:error, :invalid_value}

  defp stringify(value) do
    case safe_to_string(value) do
      {:ok, string} ->
        if String.trim(string) == "", do: {:error, :invalid_value}, else: {:ok, string}

      :error ->
        {:error, :invalid_value}
    end
  end

  defp safe_to_string(value) when is_binary(value), do: {:ok, value}

  defp safe_to_string(value) do
    {:ok, to_string(value)}
  rescue
    _ -> :error
  end
end
