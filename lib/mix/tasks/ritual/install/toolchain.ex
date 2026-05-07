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

  # Variant of `Igniter.include_or_create_file/3` that does not assume the
  # file is Elixir source. Igniter's helper hardcodes
  # `Rewrite.Source.Ex.from_string/2` in its create branch — when the
  # rendered content is not parseable Elixir (e.g. `erlang 28.3` in
  # `.tool-versions`), Sourceror raises a `SyntaxError` from inside Igniter.
  # `mise.toml` happens to be parseable as Elixir today (`[tools]` is a list
  # literal, and `key = "value"` is a `Kernel.=/2` call) but that is an
  # accident of TOML's syntax overlap; we treat both formats uniformly here.
  #
  # The flow mirrors the upstream helper:
  #
  #   1. Pull any existing source into `igniter.rewrite` via
  #      `include_existing_file/2`, which uses `source_handler/2` and so
  #      picks the generic `Rewrite.Source` for files without an `.ex`/`.exs`
  #      extension. In test mode, this reads from `:test_files` assigns.
  #   2. If a source now exists for `path`, the file pre-existed — preserve.
  #   3. Otherwise, build a generic source with our rendered content and put
  #      it on the rewrite directly.
  defp include_or_create_plain_file(igniter, path, contents) do
    igniter = Igniter.include_existing_file(igniter, path)

    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      source = Rewrite.Source.from_string(contents, path: path)
      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
    end
  end
end
