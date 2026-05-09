defmodule Ritual.Overwrite do
  @moduledoc """
  Per-target overwrite gating for Ritual installers.

  When an installer is about to clobber an existing file or AST construct,
  it consults `prompt?/2` to decide. The default behaviour is:

    * `--force` was passed: always overwrite (no prompt).
    * Non-interactive shell (`Mix.Shell.Process`, `Mix.Shell.Quiet`, ...):
      always preserve (no prompt — the prompt would deadlock waiting on
      stdin that nothing will ever write).
    * Interactive shell (`Mix.Shell.IO`): prompt the user with
      `"Overwrite <label>?"` defaulting to `:no`.

  The module is intentionally tiny and stateless — installers call into it
  at the exact decision points where a write would otherwise silently
  proceed or be silently skipped.

  ## Test mode

  Under `Igniter.Test.test_project/1` the active shell is `Mix.Shell.Process`,
  so `interactive?/0` returns `false` and the default-preserve branch is
  exercised. Tests that want to assert the overwrite path inject the
  `--force` flag through `igniter.args.options[:force]` rather than
  simulating an interactive Y answer.
  """

  @doc """
  Returns `true` when the caller should overwrite the existing target.

  See the moduledoc for the decision matrix.
  """
  @spec prompt?(Igniter.t(), String.t()) :: boolean()
  def prompt?(%Igniter{} = igniter, label) when is_binary(label) do
    cond do
      forced?(igniter) -> true
      test_mode?(igniter) -> false
      not interactive?() -> false
      true -> Mix.shell().yes?("Overwrite #{label}?", default: :no)
    end
  end

  # Under `Igniter.Test.test_project/1`, `Mix.shell()` is the same
  # `Mix.Shell.IO` used in production runs — there is no automatic test
  # shell swap. Treat the test-mode assign as a hard non-interactive
  # marker so test runs don't print spurious "Overwrite ...?" prompts.
  defp test_mode?(igniter), do: igniter.assigns[:test_mode?] == true

  @doc """
  Returns whether the `--force` flag was passed to the current task.
  """
  @spec forced?(Igniter.t()) :: boolean()
  def forced?(%Igniter{args: %{options: options}}) when is_list(options) do
    Keyword.get(options, :force, false) == true
  end

  def forced?(_igniter), do: false

  @doc """
  Returns whether the current Mix shell is the only built-in that can
  actually answer prompts (`Mix.Shell.IO`).

  Mirrors the heuristic used by `Mix.Tasks.Ritual.Bootstrap`.
  """
  @spec interactive?() :: boolean()
  def interactive?, do: Mix.shell() == Mix.Shell.IO
end
