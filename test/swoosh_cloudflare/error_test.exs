defmodule SwooshCloudflare.ErrorTest do
  use ExUnit.Case, async: true

  alias SwooshCloudflare.Error

  defp body(code), do: %{"errors" => [%{"code" => code, "message" => "x"}]}

  test "maps known Cloudflare codes" do
    assert {400, :invalid_email, _} = Error.from_response(400, body(10202))
    assert {403, :sending_disabled, _} = Error.from_response(403, body(10203))
  end

  test "known code takes precedence over status" do
    assert {500, :invalid_request, _} = Error.from_response(500, body(10001))
    assert {401, :account_suspended, _} = Error.from_response(401, body(10207))
  end

  test "falls back on status for unknown codes" do
    assert {401, :authentication_error, _} = Error.from_response(401, body(99999))
    assert {403, :forbidden, _} = Error.from_response(403, body(99999))
    assert {404, :not_found, _} = Error.from_response(404, body(99999))
    assert {429, :rate_limited, _} = Error.from_response(429, body(99999))
    assert {502, :server_error, _} = Error.from_response(502, body(99999))
  end

  test "falls back on status for bodies without a usable code" do
    for b <- ["<html>Bad Gateway</html>", nil, %{}, %{"errors" => []}, %{"errors" => "oops"}] do
      assert {502, :server_error, ^b} = Error.from_response(502, b)
      assert {401, :authentication_error, ^b} = Error.from_response(401, b)
    end
  end

  test "keeps :unknown_error for other statuses and never raises" do
    assert {400, :unknown_error, _} = Error.from_response(400, "bad")
    assert {418, :unknown_error, _} = Error.from_response(418, nil)
    assert {600, :unknown_error, _} = Error.from_response(600, nil)
  end
end
