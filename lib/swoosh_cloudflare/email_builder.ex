defmodule SwooshCloudflare.EmailBuilder do
  @moduledoc false

  @spec build(Swoosh.Email.t()) :: map()
  def build(%Swoosh.Email{} = email) do
    %{}
    |> put_required(email)
    |> put_optional("cc", format_addresses(email.cc))
    |> put_optional("bcc", format_addresses(email.bcc))
    |> put_optional("reply_to", format_address(email.reply_to))
    |> put_optional("headers", email.headers)
    |> put_optional("attachments", build_attachments(email.attachments))
  end

  defp put_required(payload, email) do
    payload
    |> Map.put("to", format_addresses(email.to))
    |> Map.put("from", format_address(email.from))
    |> Map.put("subject", email.subject)
    |> put_optional("html", email.html_body)
    |> put_optional("text", email.text_body)
  end

  defp put_optional(payload, _key, value) when value in [nil, [], %{}], do: payload
  defp put_optional(payload, key, value), do: Map.put(payload, key, value)

  defp format_addresses(addresses) when is_list(addresses) do
    Enum.map(addresses, &format_address/1)
  end

  defp format_address(nil), do: nil
  defp format_address({name, email}) when name not in [nil, ""], do: "#{name} <#{email}>"
  defp format_address({_name, email}), do: email
  defp format_address(email) when is_binary(email), do: email

  defp build_attachments([]), do: nil

  defp build_attachments(attachments) do
    Enum.map(attachments, &build_attachment/1)
  end

  defp build_attachment(%Swoosh.Attachment{} = att) do
    %{
      "filename" => att.filename,
      "content" => att |> read_data() |> Base.encode64(),
      "mimetype" => att.content_type
    }
  end

  defp read_data(%Swoosh.Attachment{data: nil, path: path}) when not is_nil(path),
    do: File.read!(path)

  defp read_data(%Swoosh.Attachment{data: data}),
    do: data
end
