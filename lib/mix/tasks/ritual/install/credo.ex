defmodule Mix.Tasks.Ritual.Install.Credo do
  @shortdoc "Add the Credo dependency and write `.credo.exs` based on detected project shape."

  @moduledoc """
  #{@shortdoc}

  Performs two transformations:

    * Adds `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` to `mix.exs`
      via `Igniter.Project.Deps.add_dep/3`. An existing `:credo` declaration is
      preserved (no version clobbering, no duplicate entry).
    * Creates a `.credo.exs` config at the project root, using the umbrella
      template when `Ritual.Detect.umbrella?/1` is true and the default
      template otherwise. An existing `.credo.exs` is left untouched.

  Both steps are idempotent — running the task twice produces the same
  `mix.exs` and `.credo.exs` as running it once.

  ## Templates

  Templates live under `priv/templates/credo/`:

    * `default.credo.exs.eex` — single-app and Hex-package projects
    * `umbrella.credo.exs.eex` — adds `apps/*/{lib,src,test}/` to `files.included`

  Both templates are EEx-rendered (no interpolations today) so future flags
  (e.g. `--max-line-length`) can pass assigns without changing the call site.
  """

  use Igniter.Mix.Task

  alias Ritual.Detect

  @credo_dep {:credo, "~> 1.7", only: [:dev, :test], runtime: false}

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.credo",
      schema: [force: :boolean],
      defaults: [force: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> add_credo_dep()
    |> write_credo_config()
  end

  defp add_credo_dep(igniter) do
    # `on_exists: :skip` keeps an existing :credo declaration intact (version,
    # opts, env list). Without it, `add_dep` defaults to :overwrite, which
    # would silently replace user customisations on every run. Users on an
    # outdated version must bump it themselves.
    Igniter.Project.Deps.add_dep(igniter, @credo_dep, on_exists: :skip)
  end

  defp write_credo_config(igniter) do
    template =
      if Detect.umbrella?(igniter) do
        "umbrella.credo.exs.eex"
      else
        "default.credo.exs.eex"
      end

    source = Application.app_dir(:ritual, ["priv", "templates", "credo", template])
    contents = EEx.eval_file(source, assigns: [])

    # Default behaviour preserves any user-authored `.credo.exs` (read from
    # disk or, in test mode, from the test fixture). With `--force` (or an
    # interactive `y` to the overwrite prompt) the file is regenerated from
    # the template. Idempotent in either branch.
    Ritual.IgniterCompat.write_or_create_elixir_file(
      igniter,
      ".credo.exs",
      contents,
      ".credo.exs"
    )
  end
end
