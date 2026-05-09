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
    * Appends `/priv/plts/*.plt` and `/priv/plts/*.plt.hash` to an existing
      `.gitignore` (line-exact check; existing entries are preserved). If
      the project has no `.gitignore`, this step is a no-op — Ritual does
      not create one.

  All four steps are idempotent — running the task twice produces the same
  `mix.exs`, `.dialyzer_ignore.exs`, and `.gitignore` as running it once.
  """

  use Igniter.Mix.Task

  alias Ritual.Detect

  @dialyxir_dep {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.dialyzer",
      schema: [force: :boolean],
      defaults: [force: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> add_dialyxir_dep()
    |> configure_dialyzer()
    |> write_ignore_file()
    |> ensure_plt_gitignore()
  end

  defp ensure_plt_gitignore(igniter) do
    Ritual.IgniterCompat.ensure_gitignore_lines(igniter, [
      "/priv/plts/*.plt",
      "/priv/plts/*.plt.hash"
    ])
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
    canonical = canonical_dialyzer_block(plt_name)

    # Set the whole `:dialyzer` keyword in one shot. The updater receives
    # `nil` if the key is absent (we materialise the canonical block) or a
    # zipper at the existing value. With overwrite confirmation we replace
    # the existing value with the canonical block; otherwise we hand the
    # zipper back unchanged so the user's customisations survive verbatim.
    Igniter.Project.MixProject.update(igniter, :project, [:dialyzer], fn
      nil ->
        {:ok, {:code, canonical}}

      zipper ->
        if Ritual.Overwrite.prompt?(igniter, "dialyzer keyword in mix.exs") do
          {:ok, {:code, canonical}}
        else
          {:ok, zipper}
        end
    end)
  end

  # Built outside the closure (which would re-evaluate `quote` per-call) and
  # passed in by reference. The `unquote(...)` interpolates the per-project
  # PLT path so the canonical block is concrete Elixir AST, not a template.
  defp canonical_dialyzer_block(plt_name) do
    quote do
      [
        plt_local_path: unquote("priv/plts/#{plt_name}.plt"),
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:ex_unit, :mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    end
  end

  defp write_ignore_file(igniter) do
    source = Application.app_dir(:ritual, ["priv", "templates", "dialyzer", "ignore.exs"])
    contents = File.read!(source)

    # Default preserves any user-authored `.dialyzer_ignore.exs`; `--force`
    # (or an interactive `y` answer) regenerates it from the template.
    Ritual.IgniterCompat.write_or_create_elixir_file(
      igniter,
      ".dialyzer_ignore.exs",
      contents,
      ".dialyzer_ignore.exs"
    )
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
