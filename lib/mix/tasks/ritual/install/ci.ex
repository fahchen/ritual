defmodule Mix.Tasks.Ritual.Install.Ci do
  @shortdoc "Write a GitHub Actions CI workflow tuned to the project's shape."

  @moduledoc """
  #{@shortdoc}

  Writes one of two workflow shapes depending on `Ritual.Detect.hex_package?/1`:

    * **Default (mise style)** — single-job `.github/workflows/ci.yml` plus a
      composite setup action at `.github/workflows/actions/setup/action.yml`.
      Tool versions come from `mise.toml` / `.tool-versions` via
      `jdx/mise-action`. This matches the toolchain installer's output and is
      the right default for applications and umbrella projects.

    * **Hex package (setup-beam matrix style)** — `.github/workflows/ci.yml`
      with `erlef/setup-beam` and a `matrix:` of Elixir/OTP version pairs. One
      row is flagged `lint: lint` and runs format/credo/dialyzer/test; other
      rows run only `mix test` to verify cross-version compatibility. No
      composite setup action is written — the matrix workflow is
      self-contained.

  Existing files are left untouched: re-running the task will not clobber a
  hand-edited `ci.yml` or a customised composite action.

  Both shapes are idempotent — running the task twice produces the same files
  as running it once.

  ## v0 has no flags

  `--style` and `--matrix` flags are intentionally not exposed yet. Auto-
  selection on `package/0` covers the two common cases. If you need to force a
  shape, run the task once and edit the generated file.
  """

  use Igniter.Mix.Task

  import Ritual.IgniterCompat, only: [write_or_create_plain_file: 4]

  alias Ritual.Ci
  alias Ritual.Detect

  @ci_workflow ".github/workflows/ci.yml"
  @setup_action ".github/workflows/actions/setup/action.yml"

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.ci",
      schema: [force: :boolean],
      defaults: [force: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    if Detect.hex_package?(igniter) do
      install_setup_beam_style(igniter)
    else
      install_mise_style(igniter)
    end
  end

  defp install_mise_style(igniter) do
    igniter
    |> write_or_create_plain_file(@ci_workflow, Ci.mise_ci(), @ci_workflow)
    |> write_or_create_plain_file(@setup_action, Ci.mise_setup_action(), @setup_action)
  end

  defp install_setup_beam_style(igniter) do
    write_or_create_plain_file(igniter, @ci_workflow, Ci.setup_beam_ci(), @ci_workflow)
  end
end
