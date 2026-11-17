defmodule SwooshCloudflare.Suppressions do
  @moduledoc """
  Manage the Cloudflare Email Service suppression list.

  Every function takes the same `config` keyword list as the mailer
  (`:api_token`, `:account_id`, optionally `:base_url`):

      config = Application.get_env(:my_app, MyApp.Mailer)

      {:ok, %{suppressions: list, next_cursor: cursor}} =
        SwooshCloudflare.Suppressions.list(config, reason: :hard_bounce, per_page: 100)

      {:ok, suppression} = SwooshCloudflare.Suppressions.get("id", config)

      {:ok, _} =
        SwooshCloudflare.Suppressions.create("bob@example.com", config,
          scope: {:sending_domain, "mail.example.com"},
          note: "asked to stop",
          expires_at: ~U[2030-01-01 00:00:00Z]
        )

      {:ok, _} = SwooshCloudflare.Suppressions.update("id", config, expires_at: nil, note: "")
      {:ok, _} = SwooshCloudflare.Suppressions.delete("id", config)

      {:ok, _} =
        SwooshCloudflare.Suppressions.import([%{email: "a@example.com"}, [email: "b@example.com"]], config)

  Suppressions are returned as decoded from Cloudflare, with string keys
  (`"id"`, `"email"`, `"reason"`, `"created_at"`, `"expires_at"`, `"read_only"`,
  `"note"`, `"scope"`).

  Errors use the same shapes as the mailer: `{:error, {status, reason, body}}`,
  `{:error, {429, :rate_limited, retry_after}}`, or a network error term.
  """

  alias SwooshCloudflare.Client

  @max_import 1000

  @type config :: keyword()
  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  Lists suppressions, one page at a time.

  Options (all optional, only given ones are sent): `:cursor`, `:email`,
  `:per_page` (max 1000), `:reason` (`:manual`, `:complaint`, `:hard_bounce`,
  `:soft_bounce`, `:policy`), `:scope_type` (`:account`, `:sending_domain`),
  `:scope_value` (requires `scope_type: :sending_domain`) and `:search`.

  Returns `{:ok, %{suppressions: [map], next_cursor: String.t() | nil}}`.
  Pass `next_cursor` as `:cursor` to fetch the next page.
  """
  @spec list(config(), keyword()) ::
          {:ok, %{suppressions: [map()], next_cursor: String.t() | nil}} | {:error, term()}
  def list(config, opts \\ []) do
    params =
      for key <- [:cursor, :email, :per_page, :reason, :scope_type, :scope_value, :search],
          Keyword.get(opts, key) != nil,
          do: {key, to_string(Keyword.fetch!(opts, key))}

    with {:ok, body} <- Client.request(:get, "/suppressions", config, params: params) do
      {:ok,
       %{
         suppressions: if(is_list(body["result"]), do: body["result"], else: []),
         next_cursor: get_in_info(body, "next_cursor")
       }}
    end
  end

  @doc "Fetches a single suppression by id."
  @spec get(String.t(), config()) :: result()
  def get(id, config), do: simple(:get, "/suppressions/#{encode(id)}", config, [])

  @doc """
  Creates a suppression.

  Options: `:scope` (`:account` or `{:sending_domain, "domain"}`; defaults to
  account), `:note`, and `:expires_at` (a `DateTime` or an ISO8601 string;
  omit for a permanent suppression).
  """
  @spec create(String.t(), config(), keyword()) :: result()
  def create(email, config, opts \\ []) do
    simple(:post, "/suppressions", config, json: build_item(Keyword.put(opts, :email, email)))
  end

  @doc """
  Updates a suppression's `:note` and/or `:expires_at`.

  An omitted option leaves the field unchanged. `expires_at: nil` makes the
  suppression permanent and `note: ""` clears the note. The scope cannot be changed.
  """
  @spec update(String.t(), config(), keyword()) :: result()
  def update(id, config, opts) do
    body =
      %{}
      |> put_if_key(opts, :expires_at, "expires_at", &format_expires_at/1)
      |> put_if_key(opts, :note, "note", & &1)

    simple(:patch, "/suppressions/#{encode(id)}", config, json: body)
  end

  @doc "Deletes a suppression by id."
  @spec delete(String.t(), config()) :: result()
  def delete(id, config), do: simple(:delete, "/suppressions/#{encode(id)}", config, [])

  @doc """
  Creates up to 1000 suppressions in one request.

  Each item is a map or keyword list with the same keys as `create/3`
  (`:email` required, `:scope`, `:note`, `:expires_at`). Raises `ArgumentError`
  for more than 1000 items.
  """
  @spec import([map() | keyword()], config()) :: result()
  def import(items, config) when is_list(items) do
    if length(items) > @max_import do
      raise ArgumentError, "cannot import more than #{@max_import} suppressions at once"
    end

    body = %{"items" => Enum.map(items, &build_item(Enum.to_list(&1)))}
    simple(:post, "/suppressions/bulk", config, json: body)
  end

  defp simple(method, path, config, req_opts) do
    with {:ok, body} <- Client.request(method, path, config, req_opts) do
      {:ok, body["result"]}
    end
  end

  defp build_item(opts) do
    email = Keyword.get(opts, :email) || raise ArgumentError, ":email is required"

    %{"email" => email}
    |> put_if_present(opts, :expires_at, "expires_at", &format_expires_at/1)
    |> put_if_present(opts, :note, "note", & &1)
    |> put_if_present(opts, :scope, "scope", &format_scope/1)
  end

  defp put_if_present(map, opts, key, name, fun) do
    case Keyword.get(opts, key) do
      nil -> map
      value -> Map.put(map, name, fun.(value))
    end
  end

  defp put_if_key(map, opts, key, name, fun) do
    if Keyword.has_key?(opts, key),
      do: Map.put(map, name, fun.(Keyword.get(opts, key))),
      else: map
  end

  defp format_expires_at(nil), do: nil
  defp format_expires_at(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_expires_at(value) when is_binary(value), do: value

  defp format_scope(:account), do: %{"type" => "account"}

  defp format_scope({:sending_domain, domain}) when is_binary(domain),
    do: %{"type" => "sending_domain", "value" => domain}

  defp get_in_info(%{"result_info" => %{} = info}, key), do: info[key]
  defp get_in_info(_, _), do: nil

  defp encode(id), do: URI.encode(to_string(id), &URI.char_unreserved?/1)
end
