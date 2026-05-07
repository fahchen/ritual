defmodule Mix.Tasks.Ritual.Install.Toolchain do
  @shortdoc "Pin Erlang/OTP and Elixir versions in `mise.toml` (default) or `.tool-versions`."

  @moduledoc """
  #{@shortdoc}

  Writes a toolchain version pin file at the project root.

    * Default: `mise.toml` with a `[tools]` table.
    * With `--tool-versions`: `.tool-versions` in the asdf-compatible
      `tool version` format.

  Both formats are populated from the runtime via `Ritual.Toolchain` —
  Elixir comes from `System.version/0` with an `-otp-<major>` suffix, and
  Erlang/OTP is read from the runtime's `OTP_VERSION` file (with a fallback
  to the bare OTP major when that file is unreadable).

  An existing `mise.toml` (or `.tool-versions` when `--tool-versions` is
  passed) is **never** overwritten — the entire content is preserved
  verbatim. This protects projects that already pin extra tools, custom
  `[tasks]`, or `[env]` blocks (mise) or additional language entries
  (`.tool-versions`).

  Both modes are idempotent — running the task twice produces the same
  file as running it once.

  ## Switching formats

  The task does not migrate between formats. If a project currently uses
  `.tool-versions` and you want to switch to mise, delete `.tool-versions`
  first; otherwise the run will succeed but only `mise.toml` will be
  created — both files would then exist, and your tooling would have to
  decide which wins.
  """

  use Igniter.Mix.Task

  import Ritual.IgniterCompat, only: [include_or_create_plain_file: 3]

  alias Ritual.Toolchain

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.toolchain",
      schema: [tool_versions: :boolean],
      defaults: [tool_versions: false],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    if igniter.args.options[:tool_versions] do
      igniter
      |> include_or_create_plain_file(".tool-versions", Toolchain.tool_versions())
      |> maybe_dual_format_notice(".tool-versions", "mise.toml")
    else
      igniter
      |> include_or_create_plain_file("mise.toml", Toolchain.mise_toml())
      |> maybe_dual_format_notice("mise.toml", ".tool-versions")
    end
  end

  defp maybe_dual_format_notice(igniter, written, other) do
    if File.exists?(other) do
      Igniter.add_notice(igniter, """
      Both `#{written}` and `#{other}` now exist in this project.

      mise and asdf will both pick whichever file matches their search order
      first; the result is tool-dependent and may not be what you want.
      Delete `#{other}` if `#{written}` is the canonical pin.
      """)
    else
      igniter
    end
  end
end
