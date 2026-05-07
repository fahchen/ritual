defmodule Ritual.IgniterCompat do
  @moduledoc """
  Compatibility shims for working around Igniter quirks that Ritual installers
  hit when writing non-Elixir files (YAML workflows, `.tool-versions`, etc.).

  The functions here are intentionally narrow — each one mirrors an upstream
  Igniter helper but sidesteps a known limitation. As Igniter evolves and the
  underlying issues are fixed, prefer migrating callers back to the upstream
  API and removing entries from this module.
  """

  @doc """
  Variant of `Igniter.include_or_create_file/3` that does not assume the file
  is Elixir source.

  Igniter's helper hardcodes `Rewrite.Source.Ex.from_string/2` in its create
  branch (see `deps/igniter/lib/igniter.ex` `:728-732`). When the rendered
  content is not parseable Elixir (e.g. `erlang 28.3` in `.tool-versions`,
  YAML in `.github/workflows/ci.yml`), Sourceror raises a `SyntaxError` from
  inside Igniter.

  Some non-Elixir formats happen to parse as Elixir today (`mise.toml` with
  only `[tools]` and `key = "value"` lines is a coincidence of TOML/Elixir
  syntax overlap), but adding `[env] FOO = "bar"` would break that. This
  helper treats every plain file uniformly.

  Mirrors the upstream flow:

    1. Pull any existing source into `igniter.rewrite` via
       `include_existing_file/2`, which uses `source_handler/2` and so picks
       the generic `Rewrite.Source` for files without an `.ex`/`.exs`
       extension. In test mode, this reads from `:test_files` assigns.
    2. If a source now exists for `path`, the file pre-existed — preserve.
    3. Otherwise, build a generic source with the rendered content and put
       it on the rewrite directly.
  """
  @spec include_or_create_plain_file(Igniter.t(), Path.t(), String.t()) :: Igniter.t()
  def include_or_create_plain_file(igniter, path, contents) do
    igniter = Igniter.include_existing_file(igniter, path)

    if Rewrite.has_source?(igniter.rewrite, path) do
      igniter
    else
      source = Rewrite.Source.from_string(contents, path: path)
      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, source)}
    end
  end
end
