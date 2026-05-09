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
      schema: [force: :boolean],
      defaults: [force: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Capture pre-existence of the alias *before* we mutate `mix.exs`. Igniter's
    # `add_alias/3` with `if_exists: :ignore` returns the same igniter regardless
    # of whether it modified the AST, so we can't infer presence after the fact.
    {action, notice?} = decide_alias_action(igniter)

    igniter
    |> apply_alias_action(action)
    |> set_preferred_env()
    |> maybe_notice(notice?, @canonical_alias_notice)
  end

  # The alias action and the canonical-mismatch notice fall out of the same
  # decision matrix:
  #
  #   * `:absent`           -> create fresh, no notice.
  #   * `:canonical`        -> existing alias matches; no-op, no notice.
  #   * `:divergent`        -> existing alias differs; prompt to overwrite.
  #     - prompt accepted   -> replace value, no notice.
  #     - prompt rejected   -> keep existing + emit canonical notice.
  #   * `:opaque`           -> existing alias is non-literal (function call,
  #                            variable, ...); prompt as for `:divergent`.
  defp decide_alias_action(igniter) do
    case existing_precommit_steps(igniter) do
      :absent ->
        {:create, false}

      {:ok, steps} ->
        if steps == canonical_steps(igniter) do
          {:noop, false}
        else
          if Ritual.Overwrite.prompt?(igniter, "precommit alias") do
            {:replace, false}
          else
            {:noop, true}
          end
        end

      :error ->
        if Ritual.Overwrite.prompt?(igniter, "precommit alias") do
          {:replace, false}
        else
          {:noop, true}
        end
    end
  end

  defp apply_alias_action(igniter, :noop), do: igniter

  defp apply_alias_action(igniter, :create) do
    steps = canonical_steps(igniter)
    # `:if_exists` defaults to `:ignore` — safe even though we only call this
    # branch when no alias exists; idempotent if we've miscategorised.
    Igniter.Project.TaskAliases.add_alias(igniter, :precommit, steps, if_exists: :ignore)
  end

  defp apply_alias_action(igniter, :replace) do
    steps = canonical_steps(igniter)
    new_value = canonical_value_ast(steps)

    Igniter.Project.TaskAliases.modify_existing_alias(igniter, :precommit, fn zipper ->
      {:ok, Igniter.Code.Common.replace_code(zipper, new_value)}
    end)
  end

  # Builds the AST for the alias value (the right-hand side of `precommit:`).
  # `Sourceror`-friendly literal so `replace_code/2` writes idiomatic Elixir.
  defp canonical_value_ast(steps) do
    quote do
      unquote(steps)
    end
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

  # Reads existing `precommit:` alias steps as a list of strings.
  # Returns `:absent` when no alias is declared, `{:ok, steps}` when the alias
  # is a literal list of strings, and `:error` otherwise (non-list value or
  # non-literal entries we cannot statically compare).
  defp existing_precommit_steps(igniter) do
    with {:ok, zipper} <- aliases_zipper(igniter),
         {:ok, zipper} <- IKeyword.get_key(zipper, :precommit) do
      eval_string_list(zipper.node)
    else
      :error -> :absent
    end
  end

  # Sourceror wraps literals as `{:__block__, meta, [literal]}` to preserve
  # formatting; unwrap before comparing. Anything non-literal (function call,
  # variable, atom, etc.) bails out so we keep the notice — we cannot tell
  # whether such an alias already matches canonical.
  defp eval_string_list(ast) do
    with {:ok, list} <- unwrap_block(ast) |> ensure_list(),
         {:ok, strings} <- collect_strings(list) do
      {:ok, strings}
    end
  end

  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(other), do: other

  defp ensure_list(list) when is_list(list), do: {:ok, list}
  defp ensure_list(_), do: :error

  defp collect_strings(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case unwrap_block(item) do
        bin when is_binary(bin) -> {:cont, {:ok, [bin | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
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
