defmodule SwooshCloudflare.Subdomains do
  @moduledoc """
  Manage Cloudflare Email Service sending subdomains.

  Sending subdomains are scoped to a zone, so every function takes the `zone_id`
  as its first argument. The `config` keyword list is the same as the mailer's;
  only `:api_token` is required (`:account_id` is not used here), and
  `:base_url` and `:req_options` are honoured as usual.

      config = Application.get_env(:my_app, MyApp.Mailer)
      zone_id = "023e105f4ecef8ad9ca31a8372d0c353"

      {:ok, subdomains} = SwooshCloudflare.Subdomains.list(zone_id, config)
      {:ok, subdomain} = SwooshCloudflare.Subdomains.create(zone_id, "send.example.com", config)
      {:ok, subdomain} = SwooshCloudflare.Subdomains.get(zone_id, subdomain["tag"], config)

      {:ok, _} =
        SwooshCloudflare.Subdomains.update(zone_id, subdomain["tag"], config,
          drop_suppressed_recipients: true,
          preview_enabled: false
        )

      {:ok, records} = SwooshCloudflare.Subdomains.dns_records(zone_id, subdomain["tag"], config)
      {:ok, _} = SwooshCloudflare.Subdomains.delete(zone_id, subdomain["tag"], config)

  The `id` argument is the subdomain `"tag"` returned by Cloudflare.

  Subdomains are returned as decoded from Cloudflare, with string keys
  (`"tag"`, `"name"`, `"enabled"`, `"created"`, `"modified"`, `"dkim_selector"`,
  `"return_path_domain"`, `"drop_suppressed_recipients"`, `"preview_enabled"`).

  The API token needs permission to edit the zone's Email Sending settings.

  Errors use the same shapes as the mailer: `{:error, {status, reason, body}}`,
  `{:error, {429, :rate_limited, retry_after}}`, or a network error term.
  """

  alias SwooshCloudflare.Client

  @type config :: keyword()
  @type result :: {:ok, term()} | {:error, term()}

  @doc "Lists the sending subdomains of a zone."
  @spec list(String.t(), config()) :: {:ok, [map()]} | {:error, term()}
  def list(zone_id, config) do
    with {:ok, result} <- simple(:get, base(zone_id), config, []) do
      {:ok, if(is_list(result), do: result, else: [])}
    end
  end

  @doc "Fetches a single sending subdomain by id."
  @spec get(String.t(), String.t(), config()) :: result()
  def get(zone_id, id, config), do: simple(:get, one(zone_id, id), config, [])

  @doc "Creates a sending subdomain with the given `name` (for example `\"send.example.com\"`)."
  @spec create(String.t(), String.t(), config()) :: result()
  def create(zone_id, name, config) when is_binary(name) do
    simple(:post, base(zone_id), config, json: %{"name" => name})
  end

  @doc """
  Updates a sending subdomain.

  Options (only given ones are sent): `:drop_suppressed_recipients` and
  `:preview_enabled`, both booleans.
  """
  @spec update(String.t(), String.t(), config(), keyword()) :: result()
  def update(zone_id, id, config, opts) do
    body =
      for key <- [:drop_suppressed_recipients, :preview_enabled],
          Keyword.has_key?(opts, key),
          into: %{},
          do: {Atom.to_string(key), Keyword.fetch!(opts, key)}

    simple(:patch, one(zone_id, id), config, json: body)
  end

  @doc "Deletes a sending subdomain by id."
  @spec delete(String.t(), String.t(), config()) :: result()
  def delete(zone_id, id, config), do: simple(:delete, one(zone_id, id), config, [])

  @doc """
  Fetches the DNS records required to verify a sending subdomain.

  Returns `{:ok, [record]}` with each record decoded with string keys.
  """
  @spec dns_records(String.t(), String.t(), config()) :: {:ok, [map()]} | {:error, term()}
  def dns_records(zone_id, id, config) do
    with {:ok, result} <- simple(:get, one(zone_id, id) <> "/dns", config, []) do
      {:ok, if(is_list(result), do: result, else: [])}
    end
  end

  defp simple(method, path, config, req_opts) do
    with {:ok, body} <- Client.call(method, path, config, req_opts) do
      {:ok, body["result"]}
    end
  end

  defp base(zone_id), do: "/zones/#{encode(zone_id)}/email/sending/subdomains"
  defp one(zone_id, id), do: "#{base(zone_id)}/#{encode(id)}"

  defp encode(id), do: URI.encode(to_string(id), &URI.char_unreserved?/1)
end
