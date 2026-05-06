defmodule Ritual.MixProject do
  use Mix.Project

  def project do
    [
      app: :ritual,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
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
      links: %{}
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.7", runtime: false}
    ]
  end
end
