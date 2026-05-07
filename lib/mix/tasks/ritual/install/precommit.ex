defmodule Mix.Tasks.Ritual.Install.Precommit do
  @shortdoc "Add a `precommit` mix alias and register it in `cli/0` `preferred_envs`."

  @moduledoc """
  #{@shortdoc}

  Performs two transformations on `mix.exs`:

    * Adds a `precommit:` alias to `aliases/0` whose steps are the canonical
      pre-commit pipeline. Steps that depend on optional tooling are emitted
      conditionally:

          precommit: [
            "compile --warnings-as-errors",
            "deps.unlock --unused",
            "format",
            "credo --strict",   # only when :credo is declared
            "dialyzer",         # only when :dialyxir is declared
            "test"
          ]

      An existing `precommit` alias is **never** modified — replacing a
      hand-tuned alias would silently destroy local customisations. When such
      an alias is detected, a notice spells out the canonical shape so users
      can compare and merge by hand.

    * Registers `[precommit: :test]` under `cli/0` `preferred_envs`. If
      `cli/0` is missing, Igniter creates it. If `preferred_envs` already
      contains a `:precommit` mapping, it is left as-is.

  Both steps are idempotent — running the task twice produces the same
  `mix.exs` as running it once. The notice (when emitted) is also gated on
  whether the alias was already present at task entry, so it is not appended
  on every re-run.

  ## Caveats

    * Detection of an existing `precommit` alias inspects either `defp
      aliases/0` directly or an inline `aliases:` keyword in `project/0`.
      The indirect form `aliases: aliases()` (a function reference inside
      `project/0`'s keyword) is not followed — the alias is still added
      correctly via Igniter, but the notice path may not fire on a
      preexisting `precommit` alias declared via that form. The reference
      projects use the `defp aliases` form directly.

    * Tooling detection (`credo`, `dialyxir`) walks the **root** `mix.exs`
      only. In an umbrella where the optional dep is declared only in a
      child app, the corresponding step is omitted from the alias. Declare
      shared tooling deps in the umbrella root if you want them in the
      precommit pipeline.
  """

  use Igniter.Mix.Task

  alias Igniter.Code.Common
  alias Igniter.Code.Function, as: IFunction
  alias Igniter.Code.Keyword, as: IKeyword
  alias Igniter.Code.List, as: IList
  alias Ritual.Detect

  @canonical_alias_notice """
  An existing `precommit` alias was preserved. The canonical Ritual precommit
  alias is:

      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "dialyzer",
        "test"
      ]

  Steps depending on tools you have not installed (credo, dialyxir) are
  optional. Update your alias by hand if you want the missing steps.
  """

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.precommit",
      schema: [],
      defaults: [],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Capture pre-existence of the alias *before* we mutate `mix.exs`. Igniter's
    # `add_alias/3` with `if_exists: :ignore` returns the same igniter regardless
    # of whether it modified the AST, so we can't infer presence after the fact.
    alias_existed? = precommit_alias_present?(igniter)

    igniter
    |> add_precommit_alias()
    |> set_preferred_env()
    |> maybe_notice(alias_existed?, @canonical_alias_notice)
  end

  defp add_precommit_alias(igniter) do
    steps = canonical_steps(igniter)

    # `:if_exists` defaults to `:ignore` — that's exactly the desired
    # semantic: a hand-tuned alias survives verbatim. We pair this with the
    # notice path above so users still learn what the canonical alias looks
    # like.
    Igniter.Project.TaskAliases.add_alias(igniter, :precommit, steps, if_exists: :ignore)
  end

  defp set_preferred_env(igniter) do
    # `MixProject.update/4` natively handles the `cli/0` shape:
    #   * absent `cli/0` -> creates `def cli`, `preferred_envs: [precommit: :test]`
    #   * present `cli/0` without `preferred_envs` -> adds the keyword
    #   * present `preferred_envs` with other entries -> appends `:precommit`
    #   * present `preferred_envs[:precommit]` -> calls our updater with a zipper
    #     at the existing value, which we hand back unchanged (idempotent).
    Igniter.Project.MixProject.update(igniter, :cli, [:preferred_envs, :precommit], fn
      nil -> {:ok, {:code, :test}}
      zipper -> {:ok, zipper}
    end)
  end

  # Builds the alias step list, honouring detected tooling. Always-on steps
  # bracket the conditional middle section so users with neither credo nor
  # dialyxir still get a usable alias.
  defp canonical_steps(igniter) do
    credo? = Igniter.Project.Deps.has_dep?(igniter, :credo)
    dialyxir? = Igniter.Project.Deps.has_dep?(igniter, :dialyxir)

    [
      "compile --warnings-as-errors",
      "deps.unlock --unused",
      "format"
    ] ++
      if(credo?, do: ["credo --strict"], else: []) ++
      if(dialyxir?, do: ["dialyzer"], else: []) ++
      ["test"]
  end

  # Returns `true` if `mix.exs` already declares a `:precommit` key inside
  # `aliases/0` (or the inline `aliases:` keyword on `project/0`).
  defp precommit_alias_present?(igniter) do
    case aliases_zipper(igniter) do
      {:ok, zipper} -> match?({:ok, _}, IKeyword.get_key(zipper, :precommit))
      :error -> false
    end
  end

  # Navigates to the keyword list of `aliases/0` (or the `aliases:` value in
  # `project/0`). Mirrors `Igniter.Project.TaskAliases.go_to_aliases/1` but
  # is read-only (does not synthesise an `aliases/0` if missing). The
  # `aliases: aliases()` indirect form is intentionally not followed — see
  # moduledoc caveats.
  defp aliases_zipper(igniter) do
    case Detect.mix_zipper(igniter) do
      {:ok, zipper} ->
        case IFunction.move_to_defp(zipper, :aliases, 0) do
          {:ok, zipper} -> keyword_list_zipper(zipper)
          :error -> aliases_via_project(zipper)
        end

      :error ->
        :error
    end
  end

  defp aliases_via_project(zipper) do
    with {:ok, zipper} <- IFunction.move_to_def(zipper, :project, 0),
         {:ok, zipper} <- keyword_list_zipper(zipper),
         {:ok, zipper} <- IKeyword.get_key(zipper, :aliases) do
      if IList.list?(zipper), do: {:ok, zipper}, else: :error
    else
      _ -> :error
    end
  end

  defp keyword_list_zipper(zipper) do
    zipper = Common.rightmost(zipper)
    if IList.list?(zipper), do: {:ok, zipper}, else: :error
  end

  defp maybe_notice(igniter, true, msg), do: Igniter.add_notice(igniter, msg)
  defp maybe_notice(igniter, false, _msg), do: igniter
end
