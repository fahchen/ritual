defmodule Mix.Tasks.Ritual.Bootstrap do
  @shortdoc "Interactively pick which Ritual installers to run."

  @moduledoc """
  #{@shortdoc}

  Walks the same canonical installer order as `mix ritual.install` but
  prompts the user (`Install X? [Y/n]`) before composing each sub-task. The
  non-interactive `mix ritual.install` remains unchanged for CI/automation
  paths that need every installer unconditionally.

  ## Prompts and defaults

  Each prompt defaults to **Y** except `publish`, which defaults to **Y**
  only when `Ritual.Detect.hex_package?/1` reports the project as a Hex
  package and **N** otherwise. Pressing Enter accepts the default; `n`
  declines and the corresponding sub-task is skipped (`Igniter.compose_task`
  is simply not invoked for it).

  ## Options

    * `--yes` — skip every prompt and compose every sub-task. Equivalent to
      running `mix ritual.install`. Forced on automatically when Mix is not
      running through an interactive shell (e.g. `Mix.Shell.Process` in
      tests, CI without a TTY); a one-line warning is printed in that case
      so the behaviour is visible in CI logs.

    * `--tool-versions` — forwarded to `mix ritual.install.toolchain`,
      identical to the `mix ritual.install` flag.

  ## Test mode

  Under `Igniter.Test.test_project/1`, prompts cannot be answered
  interactively. Tests inject a `:bootstrap_selection` map into
  `igniter.assigns` keyed by sub-task name (e.g. `"ritual.install.credo"`)
  with boolean values. Entries that are missing fall back to each task's
  per-prompt default — `true` for everything except
  `"ritual.install.publish"`, whose default is `Ritual.Detect.hex_package?/1`.
  This matches the production prompt defaults and keeps the test suite
  free of stdin simulation. The non-interactive auto-promotion warning is
  suppressed in test mode (`igniter.assigns[:test_mode?]`) so it does not
  pollute test output.
  """

  use Igniter.Mix.Task

  alias Ritual.Detect

  @subtasks [
    {"ritual.install.format", "Install .formatter.exs?"},
    {"ritual.install.toolchain", "Install mise.toml / .tool-versions?"},
    {"ritual.install.credo", "Install Credo?"},
    {"ritual.install.dialyzer", "Install Dialyxir?"},
    {"ritual.install.precommit", "Install precommit alias?"},
    {"ritual.install.ci", "Install GitHub Actions CI workflow?"},
    {"ritual.install.publish", "Install Hex publish workflow?"}
  ]

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.bootstrap",
      # `--yes` short-circuits every prompt; `--tool-versions` is forwarded
      # verbatim through `compose_task` (which passes `argv_flags` to each
      # sub-task) — declared here so the aggregator's OptionParser run does
      # not reject it.
      schema: [yes: :boolean, tool_versions: :boolean],
      defaults: [yes: false, tool_versions: false],
      composes: Enum.map(@subtasks, fn {task, _prompt} -> task end)
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    explicit_yes? = igniter.args.options[:yes] == true
    interactive? = interactive?()

    if not explicit_yes? and not interactive? and not test_mode?(igniter) do
      Mix.shell().info("""
      mix ritual.bootstrap: non-interactive shell detected (#{inspect(Mix.shell())}); \
      auto-promoting to --yes (composes every sub-task). Pass --yes explicitly to \
      silence this warning, or use `mix ritual.install` for the same behaviour.\
      """)
    end

    yes? = explicit_yes? or not interactive?
    hex? = Detect.hex_package?(igniter)

    Enum.reduce(@subtasks, igniter, fn {task, prompt}, acc ->
      if select?(acc, task, prompt, default_for(task, hex?), yes?) do
        Igniter.compose_task(acc, task)
      else
        acc
      end
    end)
  end

  defp test_mode?(igniter), do: igniter.assigns[:test_mode?] == true

  # Every sub-task defaults to Y except publish, which mirrors whether the
  # project is actually a Hex publishable library. This keeps the prompt
  # defaults aligned with the project shape — the user just hits Enter and
  # the right thing happens.
  defp default_for("ritual.install.publish", hex?), do: hex?
  defp default_for(_other, _hex?), do: true

  defp select?(_igniter, _task, _prompt, _default, true = _yes?), do: true

  defp select?(igniter, task, prompt, default, false = _yes?) do
    cond do
      # Test-mode hook: pre-populated answer map keyed by sub-task name.
      # Missing entries fall back to the per-task default so a test only
      # has to specify the answers it cares about.
      selection = igniter.assigns[:bootstrap_selection] ->
        Map.get(selection, task, default)

      true ->
        # `Mix.shell().yes?/2`'s `:default` option flips which letter is
        # capitalised in the prompt and which answer Enter selects.
        Mix.shell().yes?(prompt, default: if(default, do: :default_yes, else: :default_no))
    end
  end

  # `Mix.Shell.IO` is the only built-in shell that actually reads from stdin;
  # `Mix.Shell.Process` (used in `mix test`) and `Mix.Shell.Quiet` cannot
  # answer prompts. Treat anything but `Mix.Shell.IO` as non-interactive and
  # auto-promote to `--yes` so the task does not deadlock waiting on stdin.
  defp interactive?, do: Mix.shell() == Mix.Shell.IO
end
