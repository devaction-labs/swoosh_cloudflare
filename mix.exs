defmodule SwooshCloudflare.MixProject do
  use Mix.Project

  @version "0.5.1"
  @source_url "https://github.com/devaction-labs/swoosh_cloudflare"

  def project do
    [
      app: :swoosh_cloudflare,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Swoosh adapter for Cloudflare Email Service",
      package: package(),
      docs: docs(),
      name: "SwooshCloudflare",
      source_url: @source_url,
      dialyzer: [plt_add_apps: [:mix, :ex_unit]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:swoosh, "~> 1.0"},
      {:req, "~> 0.5"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/swoosh_cloudflare/changelog.html"
      },
      maintainers: ["Alex Nogueira"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Adapter: [Swoosh.Adapters.Cloudflare],
        API: [SwooshCloudflare, SwooshCloudflare.Suppressions]
      ]
    ]
  end
end
