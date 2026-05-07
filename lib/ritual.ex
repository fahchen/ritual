defmodule Ritual do
  @moduledoc """
  Composable Igniter-based Mix tasks for bootstrapping Elixir/Phoenix
  projects with consistent tooling.

  This namespace module documents how the pieces fit together. The actual
  installers live under `Mix.Tasks.Ritual.Install.*`; helper modules
  used by more than one installer live alongside this one
  (`Ritual.Detect`, `Ritual.Formatter`, `Ritual.Ci`, `Ritual.Toolchain`,
  `Ritual.IgniterCompat`).

  ## Top-level

  `mix ritual.install` runs every sub-installer in sequence. See
  `Mix.Tasks.Ritual.Install` for the order and rationale.

  ## Sub-installers

    * `Mix.Tasks.Ritual.Install.Format` — `.formatter.exs`
    * `Mix.Tasks.Ritual.Install.Toolchain` — `mise.toml` or `.tool-versions`
    * `Mix.Tasks.Ritual.Install.Credo` — Credo dep + `.credo.exs`
    * `Mix.Tasks.Ritual.Install.Dialyzer` — Dialyxir dep + `dialyzer:` keyword
    * `Mix.Tasks.Ritual.Install.Precommit` — `precommit` mix alias + `cli/0`
    * `Mix.Tasks.Ritual.Install.Ci` — GitHub Actions CI workflow
    * `Mix.Tasks.Ritual.Install.Publish` — Hex publish workflow

  ## Project-shape detection

  Every installer branches on predicates from `Ritual.Detect`:

    * `umbrella?/1` — `apps_path:` in `project/0`
    * `phoenix?/1` — `:phoenix` in deps
    * `phoenix_live_view?/1` — `:phoenix_live_view` in deps
    * `hex_package?/1` — `def`/`defp package/0` in `mix.exs`
    * `app_name/1` — `:app` from `project/0`, `{:ok, atom} | :error`

  See the `README` for the user-facing tour, `task_plan.md` for the design
  history, and `findings.md` for Igniter quirks worked around in this
  codebase.
  """
end
