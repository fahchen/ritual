defmodule Ritual.MixProject do
  use Mix.Project

  @source_url "https://github.com/fahchen/ritual"
  @version "0.1.0"

  def project do
    [
      app: :ritual,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Ritual",
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Composable Igniter-based Mix tasks for bootstrapping Elixir/Phoenix " <>
      "projects with consistent tooling (credo, dialyzer, formatter, CI, mise)."
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Phil Chen"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.7", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
