defmodule SwooshCloudflare.MixProject do
  use Mix.Project

  @version "0.1.1"
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
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:swoosh, "~> 1.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Alex Nogueira"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
