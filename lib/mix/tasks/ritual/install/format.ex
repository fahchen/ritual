defmodule Mix.Tasks.Ritual.Install.Format do
  @shortdoc "Create or update `.formatter.exs` based on detected project shape."

  @moduledoc """
  #{@shortdoc}

  Drives `Ritual.Formatter` based on the predicates in `Ritual.Detect`:

    * Plain libraries: ensure the default `inputs:` is present.
    * Umbrella projects: rewrite `inputs:` and `subdirectories:` to the
      umbrella shape.
    * Phoenix projects (umbrella or not): import `:ecto`, `:ecto_sql`, and
      `:phoenix` formatter rules and register
      `Phoenix.LiveView.HTMLFormatter` as a plugin.

  Hex packages get a notice rather than an automatic `export:` block — see
  `Ritual.Formatter` moduledoc for the rationale.

  Safe to run repeatedly — every transformation is idempotent and existing
  user customisations are preserved (only missing keys are added; only
  umbrella shape forces a known-default `inputs:` to be replaced).
  """

  use Igniter.Mix.Task

  alias Ritual.Detect
  alias Ritual.Formatter

  @hex_export_notice """
  Detected a Hex-publishable project (mix.exs defines package/0).

  No `export:` block was added to `.formatter.exs`. If this library exposes
  custom DSL macros or a formatter plugin, add an `export:` keyword by hand:

      export: [
        locals_without_parens: [my_macro: 2],
        plugins: [MyLib.Formatter]
      ]
  """

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.format",
      schema: [force: :boolean],
      defaults: [force: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    umbrella? = Detect.umbrella?(igniter)
    phoenix? = Detect.phoenix?(igniter)
    hex_package? = Detect.hex_package?(igniter)

    igniter
    |> Formatter.ensure_present()
    |> maybe_apply(umbrella?, &Formatter.apply_umbrella/1)
    |> maybe_apply(phoenix?, &Formatter.apply_phoenix/1)
    |> maybe_notice(hex_package?, @hex_export_notice)
  end

  defp maybe_apply(igniter, true, fun), do: fun.(igniter)
  defp maybe_apply(igniter, false, _fun), do: igniter

  defp maybe_notice(igniter, true, msg), do: Igniter.add_notice(igniter, msg)
  defp maybe_notice(igniter, false, _msg), do: igniter
end
