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

    assert payload["to"] == [%{"address" => "alice@example.com", "name" => "Alice"}]
    assert payload["from"] == %{"address" => "sender@example.com", "name" => "Sender"}
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

  test "keeps names with commas and quotes intact in the name field" do
    email = %{base_email() | to: [{"Doe, \"Johnny\"", "john@example.com"}]}

    assert EmailBuilder.build(email)["to"] == [
             %{"address" => "john@example.com", "name" => "Doe, \"Johnny\""}
           ]
  end

  test "formats nil name and plain binary addresses as plain strings" do
    email = %{base_email() | to: [{nil, "a@example.com"}, "b@example.com"]}
    assert EmailBuilder.build(email)["to"] == ["a@example.com", "b@example.com"]
  end

  test "includes cc and bcc when present" do
    email = %{base_email() | cc: [{"Bob", "bob@example.com"}], bcc: [{"", "bcc@example.com"}]}
    payload = EmailBuilder.build(email)

    assert payload["cc"] == [%{"address" => "bob@example.com", "name" => "Bob"}]
    assert payload["bcc"] == ["bcc@example.com"]
  end

  test "includes reply_to when present" do
    email = %{base_email() | reply_to: {"Reply", "reply@example.com"}}

    assert EmailBuilder.build(email)["reply_to"] == %{
             "address" => "reply@example.com",
             "name" => "Reply"
           }
  end

  test "includes text body and omits html when only text present" do
    email = %{base_email() | html_body: nil, text_body: "plain text"}
    payload = EmailBuilder.build(email)

    assert payload["text"] == "plain text"
    refute Map.has_key?(payload, "html")
  end

  test "builds attachment with correct API fields" do
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
    assert att["type"] == "application/pdf"
    assert att["disposition"] == "attachment"
    refute Map.has_key?(att, "mimetype")
    refute Map.has_key?(att, "contentType")
  end

  test "sets disposition inline for inline attachments" do
    attachment = %Swoosh.Attachment{
      filename: "logo.png",
      data: "PNG data",
      content_type: "image/png",
      type: :inline,
      cid: nil
    }

    email = %{base_email() | attachments: [attachment]}
    [att] = EmailBuilder.build(email)["attachments"]

    assert att["disposition"] == "inline"
    assert att["type"] == "image/png"
  end

  test "sends content_id for inline attachments with a cid" do
    attachment = %Swoosh.Attachment{
      filename: "logo.png",
      data: "PNG data",
      content_type: "image/png",
      type: :inline,
      cid: "logo"
    }

    email = %{base_email() | attachments: [attachment]}
    [att] = EmailBuilder.build(email)["attachments"]

    assert att["content_id"] == "logo"
  end

  test "omits content_id for regular attachments and empty cids" do
    regular = %Swoosh.Attachment{
      filename: "a.pdf",
      data: "x",
      content_type: "application/pdf",
      type: :attachment,
      cid: "ignored"
    }

    inline_empty = %Swoosh.Attachment{
      filename: "b.png",
      data: "x",
      content_type: "image/png",
      type: :inline,
      cid: ""
    }

    email = %{base_email() | attachments: [regular, inline_empty]}
    atts = EmailBuilder.build(email)["attachments"]

    refute Enum.any?(atts, &Map.has_key?(&1, "content_id"))
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

  test "formats a single reply_to address" do
    email = %{base_email() | reply_to: {"Support", "support@example.com"}}

    assert EmailBuilder.build(email)["reply_to"] ==
             %{"address" => "support@example.com", "name" => "Support"}
  end

  test "formats a list of reply_to addresses" do
    email = %{
      base_email()
      | reply_to: [{"Support", "support@example.com"}, "help@example.com"]
    }

    assert EmailBuilder.build(email)["reply_to"] == [
             %{"address" => "support@example.com", "name" => "Support"},
             "help@example.com"
           ]
  end

  test "omits reply_to when it is an empty list" do
    email = %{base_email() | reply_to: []}

    refute Map.has_key?(EmailBuilder.build(email), "reply_to")
  end
end
