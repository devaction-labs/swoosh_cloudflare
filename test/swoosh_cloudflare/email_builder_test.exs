defmodule SwooshCloudflare.EmailBuilderTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.EmailBuilder

  defp base_email do
    %Swoosh.Email{
      to: [{"Alice", "alice@example.com"}],
      from: {"Sender", "sender@example.com"},
      subject: "Hello",
      html_body: "<p>Hi</p>"
    }
  end

  test "builds required fields" do
    payload = EmailBuilder.build(base_email())

    assert payload["to"] == ["Alice <alice@example.com>"]
    assert payload["from"] == "Sender <sender@example.com>"
    assert payload["subject"] == "Hello"
    assert payload["html"] == "<p>Hi</p>"
  end

  test "omits nil optional fields" do
    payload = EmailBuilder.build(base_email())

    refute Map.has_key?(payload, "cc")
    refute Map.has_key?(payload, "bcc")
    refute Map.has_key?(payload, "reply_to")
    refute Map.has_key?(payload, "headers")
    refute Map.has_key?(payload, "attachments")
  end

  test "formats address without name" do
    email = %{base_email() | from: {"", "sender@example.com"}}
    assert EmailBuilder.build(email)["from"] == "sender@example.com"
  end

  test "includes cc and bcc when present" do
    email = %{base_email() | cc: [{"Bob", "bob@example.com"}], bcc: [{"", "bcc@example.com"}]}
    payload = EmailBuilder.build(email)

    assert payload["cc"] == ["Bob <bob@example.com>"]
    assert payload["bcc"] == ["bcc@example.com"]
  end

  test "includes reply_to when present" do
    email = %{base_email() | reply_to: {"Reply", "reply@example.com"}}
    assert EmailBuilder.build(email)["reply_to"] == "Reply <reply@example.com>"
  end

  test "includes text body and omits html when only text present" do
    email = %{base_email() | html_body: nil, text_body: "plain text"}
    payload = EmailBuilder.build(email)

    assert payload["text"] == "plain text"
    refute Map.has_key?(payload, "html")
  end

  test "builds attachment with base64 content and mimetype" do
    attachment = %Swoosh.Attachment{
      filename: "file.pdf",
      data: "PDF content",
      content_type: "application/pdf",
      type: :attachment,
      cid: nil
    }

    email = %{base_email() | attachments: [attachment]}
    [att] = EmailBuilder.build(email)["attachments"]

    assert att["filename"] == "file.pdf"
    assert att["content"] == Base.encode64("PDF content")
    assert att["mimetype"] == "application/pdf"
    refute Map.has_key?(att, "contentType")
    refute Map.has_key?(att, "disposition")
  end

  test "reads attachment content from path when data is nil" do
    path = Path.join(System.tmp_dir!(), "swoosh_cf_test_#{System.unique_integer()}.txt")
    File.write!(path, "file content from disk")

    on_exit(fn -> File.rm(path) end)

    attachment = %Swoosh.Attachment{
      filename: "doc.txt",
      data: nil,
      path: path,
      content_type: "text/plain",
      type: :attachment,
      cid: nil
    }

    email = %{base_email() | attachments: [attachment]}
    [att] = EmailBuilder.build(email)["attachments"]

    assert att["content"] == Base.encode64("file content from disk")
  end
end
