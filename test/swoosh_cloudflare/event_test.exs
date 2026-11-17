defmodule SwooshCloudflare.EventTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Event

  @fixtures Path.expand("../fixtures/events", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures, "#{name}.json"))

  for type <- ~w(delivered deferred bounced failed rejected complained) do
    test "parses the documented #{type} example from JSON and from a map" do
      json = fixture(unquote(type))
      assert {:ok, %Event{} = event} = Event.parse(json)
      assert event.type == String.to_atom(unquote(type))
      assert event.raw_type == "cf.email.sending.message.#{unquote(type)}"
      assert event.raw == Jason.decode!(json)
      assert {:ok, ^event} = Event.parse(Jason.decode!(json))
      assert event.event_id =~ "0190d0c4"
      assert event.message_id =~ "0101018f7d0c4d9a-msg-"
      assert event.recipient == "user@example.net"
      assert event.terminal == unquote(type) not in ["deferred"]
      assert event.source["type"] == "email.sending"
      assert event.metadata["eventSchemaVersion"] == 1
      assert event.timestamp == ~U[2026-06-01 02:48:57.132Z]
      assert event.delivery["status"] == unquote(type)
    end
  end

  test "delivered carries delivery details and no other sections" do
    {:ok, event} = Event.parse(fixture("delivered"))

    assert event.sender == "noreply@example.com"
    assert event.subject == "Welcome"
    assert event.delivery["smtpStatusCode"] == "250"
    assert event.delivery["deliveryTimeMs"] == 1234
    assert is_nil(event.bounce)
    assert is_nil(event.failure)
    assert is_nil(event.rejection)
    assert is_nil(event.complaint)
  end

  test "deferred and bounced carry the bounce section" do
    {:ok, deferred} = Event.parse(fixture("deferred"))
    assert deferred.bounce["type"] == "soft"
    {:ok, bounced} = Event.parse(fixture("bounced"))

    assert bounced.bounce == %{
             "type" => "hard",
             "classification" => "permanent_failure",
             "reason" => "550 5.1.1 User unknown"
           }
  end

  test "failed, rejected and complained carry their own section" do
    {:ok, failed} = Event.parse(fixture("failed"))
    assert failed.failure == %{"reason" => "delivery_failed"}
    {:ok, rejected} = Event.parse(fixture("rejected"))
    assert rejected.rejection["reason"] == "suppressed"
    {:ok, complained} = Event.parse(fixture("complained"))
    assert complained.complaint == %{"type" => "abuse"}
    assert is_nil(complained.subject)
  end

  test "unknown types map to :unknown and keep the raw string" do
    map = %{"type" => "cf.email.sending.message.future", "payload" => %{"eventId" => "e"}}

    assert {:ok, %Event{type: :unknown, raw_type: "cf.email.sending.message.future"}} =
             Event.parse(map)
  end

  test "missing or invalid timestamp gives nil" do
    base = %{"type" => "cf.email.sending.message.delivered", "payload" => %{}}
    assert {:ok, %Event{timestamp: nil, metadata: nil}} = Event.parse(base)

    bad = Map.put(base, "metadata", %{"eventTimestamp" => "yesterday"})
    assert {:ok, %Event{timestamp: nil}} = Event.parse(bad)
  end

  test "never raises on bad input" do
    assert {:error, :invalid_json} = Event.parse("not json")
    assert {:error, :invalid_event} = Event.parse("[1,2]")
    assert {:error, :invalid_event} = Event.parse("null")
    assert {:error, :invalid_event} = Event.parse(%{})
    assert {:error, :invalid_event} = Event.parse(%{"type" => "x"})
    assert {:error, :invalid_event} = Event.parse(%{"type" => 1, "payload" => %{}})
    assert {:error, :invalid_event} = Event.parse(%{"type" => "x", "payload" => "p"})
    assert {:error, :invalid_event} = Event.parse(nil)
    assert {:error, :invalid_event} = Event.parse(123)
  end
end
