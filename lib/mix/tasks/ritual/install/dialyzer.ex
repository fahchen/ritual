defmodule Mix.Tasks.Ritual.Install.Dialyzer do
  @shortdoc "Add the Dialyxir dependency, configure `dialyzer:`, and seed `.dialyzer_ignore.exs`."

  @moduledoc """
  #{@shortdoc}

  Performs three transformations:

    * Adds `{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}` to
      `mix.exs` via `Igniter.Project.Deps.add_dep/3`. An existing `:dialyxir`
      declaration is preserved (no version clobbering, no duplicate entry).
    * Injects a `dialyzer:` keyword into `project/0` of `mix.exs` with PLT
      paths derived from `Ritual.Detect.app_name/1`. When `:app` is absent
      (typical for umbrella `mix.exs`), falls back to
      `priv/plts/project.plt`. An existing `dialyzer:` keyword is left
      entirely untouched — neither merged nor diffed — so user
      customisations (extra `plt_add_apps`, custom `ignore_warnings`, etc.)
      survive verbatim.
    * Creates `.dialyzer_ignore.exs` at the project root with a documented
      empty list. An existing `.dialyzer_ignore.exs` is left untouched.

  All three steps are idempotent — running the task twice produces the same
  `mix.exs` and `.dialyzer_ignore.exs` as running it once.
  """

  use Igniter.Mix.Task

  alias Ritual.Detect

  @dialyxir_dep {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.dialyzer",
      schema: [],
      defaults: [],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> add_dialyxir_dep()
    |> configure_dialyzer()
    |> write_ignore_file()
  end

  defp add_dialyxir_dep(igniter) do
    # `on_exists: :skip` keeps an existing :dialyxir declaration intact
    # (version, opts, env list). Without it, `add_dep` defaults to
    # :overwrite, which would silently replace user customisations on every
    # run.
    Igniter.Project.Deps.add_dep(igniter, @dialyxir_dep, on_exists: :skip)
  end

  defp configure_dialyzer(igniter) do
    plt_name = plt_name(igniter)

    # Set the whole `:dialyzer` keyword in one shot. The updater receives
    # `nil` if the key is absent (we materialise the default block) or a
    # zipper at the existing value (we hand it back unchanged). Setting
    # individual sub-keys would silently fill in any user-omitted entry —
    # see Phase 6 findings entry on preserving the exact user shape.
    Igniter.Project.MixProject.update(igniter, :project, [:dialyzer], fn
      nil ->
        {:ok,
         {:code,
          quote do
            [
              plt_local_path: unquote("priv/plts/#{plt_name}.plt"),
              plt_core_path: "priv/plts/core.plt",
              plt_add_apps: [:ex_unit, :mix],
              ignore_warnings: ".dialyzer_ignore.exs"
            ]
          end}}

      zipper ->
        {:ok, zipper}
    end)
  end

  defp write_ignore_file(igniter) do
    source = Application.app_dir(:ritual, ["priv", "templates", "dialyzer", "ignore.exs"])
    contents = File.read!(source)

    # `include_or_create_file` preserves any user-authored
    # `.dialyzer_ignore.exs` (read from disk or, in test mode, from the test
    # fixture) and only writes the template when no file exists. Idempotent.
    Igniter.include_or_create_file(igniter, ".dialyzer_ignore.exs", contents)
  end

  # Umbrella `mix.exs` files commonly omit `:app`, in which case
  # `Ritual.Detect.app_name/1` returns `:error`. We fall back to a
  # generic name so the keyword still emits valid Elixir; users who
  # care can rename the `.plt` afterwards.
  defp plt_name(igniter) do
    case Detect.app_name(igniter) do
      {:ok, app} -> Atom.to_string(app)
      :error -> "project"
    end
  end
end
