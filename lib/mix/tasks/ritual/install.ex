defmodule Mix.Tasks.Ritual.Install do
  @shortdoc "Run every Ritual installer in sequence."

  @moduledoc """
  #{@shortdoc}

  Composes all of the per-tool installers in a single pipeline:

    1. `mix ritual.install.format` — `.formatter.exs`
    2. `mix ritual.install.toolchain` — `mise.toml` (or `.tool-versions`)
    3. `mix ritual.install.credo` — Credo dep + `.credo.exs`
    4. `mix ritual.install.dialyzer` — Dialyxir dep + `dialyzer:` keyword + ignore file
    5. `mix ritual.install.precommit` — `precommit` mix alias + `cli/0` env
    6. `mix ritual.install.ci` — GitHub Actions CI workflow
    7. `mix ritual.install.publish` — Hex publish workflow (Hex packages only)

  The order matters in three places:

    * **toolchain before ci** — so `mise.toml` exists when the generated
      workflow looks for it (cosmetic — humans review the diff in this
      order, no runtime dependency between installers).
    * **credo before precommit** — `precommit` calls `Deps.has_dep?(:credo)`
      to decide whether to include `mix credo --strict` in the alias.
    * **dialyzer before precommit** — same pattern with `:dialyxir`.

  Every other ordering is incidental. Issues from any sub-task accumulate
  on the igniter struct without halting the pipe; the full sequence runs
  to completion before Igniter refuses to write at the very end.

  ## Options

    * `--tool-versions` — forwarded to `mix ritual.install.toolchain`. Writes
      `.tool-versions` (asdf-compatible) instead of the default `mise.toml`.

  All sub-tasks are individually idempotent — running `mix ritual.install`
  twice produces the same project as running it once. Each sub-task also
  preserves any pre-existing user-authored files (formatter, credo config,
  CI workflows, `.dialyzer_ignore.exs`, ...) verbatim; the aggregator
  inherits that guarantee.

  ## Notices

  Sub-tasks emit notices for project shapes that need a human follow-up
  (e.g. Hex packages opting out of an automatic `export:` block, mismatched
  `.tool-versions` + `mise.toml`). Those notices bubble up unchanged to the
  aggregator's output.
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install",
      # `--tool-versions` is the only flag that fans out to a sub-task today.
      # It is declared here (not just in toolchain) so the aggregator's
      # OptionParser run accepts it; the merged sub-task schema would let it
      # through too, but listing it explicitly keeps the contract obvious in
      # `mix help ritual.install`.
      schema: [tool_versions: :boolean, force: :boolean],
      defaults: [tool_versions: false, force: false],
      composes: [
        "ritual.install.format",
        "ritual.install.toolchain",
        "ritual.install.credo",
        "ritual.install.dialyzer",
        "ritual.install.precommit",
        "ritual.install.ci",
        "ritual.install.publish"
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # `compose_task/3` (no argv) defaults to passing `igniter.args.argv_flags`
    # to each sub-task — so any flag the user gave the aggregator reaches
    # every sub-task. Sub-tasks that do not declare a flag simply ignore it:
    # `Igniter.Mix.Task.__options__!/2` calls `OptionParser.parse!/2` in
    # `:switches` mode (not `:strict`), so unknown flags fall out as
    # leftovers rather than raising. The strict `validate!/3` path only
    # fires from `Mix.Tasks.Igniter.Install`'s install-time composition,
    # not from the runtime `compose_task` chain we use here.
    igniter
    |> Igniter.compose_task("ritual.install.format")
    |> Igniter.compose_task("ritual.install.toolchain")
    |> Igniter.compose_task("ritual.install.credo")
    |> Igniter.compose_task("ritual.install.dialyzer")
    |> Igniter.compose_task("ritual.install.precommit")
    |> Igniter.compose_task("ritual.install.ci")
    |> Igniter.compose_task("ritual.install.publish")
  end
end
