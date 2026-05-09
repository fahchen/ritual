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
      %{igniter | rewrite: Rewrite.put!(igniter.rewrite, fresh_plain_source(igniter, path, contents))}
    end
  end

  # `Rewrite.Source.from_string/2` alone produces a source with
  # `updated?: false`, so Igniter's write phase treats it as untouched and
  # never persists it to disk (in-memory tests still observed the contents,
  # which is why this regression slipped through). Routing through
  # `Igniter.update_source/5` with `by: :file_creator` mirrors the upstream
  # `Igniter.create_new_file/4` create branch and marks the source dirty so
  # it actually lands on disk on apply.
  defp fresh_plain_source(igniter, path, contents) do
    ""
    |> Rewrite.Source.from_string(path: path)
    |> Igniter.update_source(igniter, :content, contents, by: :file_creator)
  end

  @doc """
  Variant of `Igniter.include_or_create_file/3` that prompts (via
  `Ritual.Overwrite.prompt?/2`) before clobbering an existing Elixir
  source file.

    * No existing file: writes the rendered contents (delegates to
      `Igniter.include_or_create_file/3`).
    * Existing file + prompt rejected (default): preserves verbatim
      (delegates to `Igniter.include_or_create_file/3`).
    * Existing file + prompt accepted (`--force` or interactive `y`):
      overwrites via `Igniter.create_new_file/4` with `on_exists: :overwrite`.
  """
  @spec write_or_create_elixir_file(Igniter.t(), Path.t(), String.t(), String.t()) :: Igniter.t()
  def write_or_create_elixir_file(igniter, path, contents, label) do
    on_disk_or_in_rewrite? =
      Rewrite.has_source?(igniter.rewrite, path) or Igniter.exists?(igniter, path)

    if on_disk_or_in_rewrite? and Ritual.Overwrite.prompt?(igniter, label) do
      Igniter.create_new_file(igniter, path, contents, on_exists: :overwrite)
    else
      Igniter.include_or_create_file(igniter, path, contents)
    end
  end

  @doc """
  Variant of `include_or_create_plain_file/3` that prompts (via
  `Ritual.Overwrite.prompt?/2`) before clobbering an existing plain file.

    * No existing source: behaves like `include_or_create_plain_file/3`
      and writes the rendered contents.
    * Existing source + prompt rejected (default): preserves the existing
      content verbatim — same as the upstream helper today.
    * Existing source + prompt accepted (`--force` or interactive `y`):
      replaces the source contents with `contents`.

  The replace path mutates the existing source in place rather than
  creating a fresh one so any other source metadata Igniter tracks
  (e.g. owner-of-creation, formatter hints) survives.
  """
  @spec write_or_create_plain_file(Igniter.t(), Path.t(), String.t(), String.t()) :: Igniter.t()
  def write_or_create_plain_file(igniter, path, contents, label) do
    igniter = Igniter.include_existing_file(igniter, path)

    cond do
      not Rewrite.has_source?(igniter.rewrite, path) ->
        %{igniter | rewrite: Rewrite.put!(igniter.rewrite, fresh_plain_source(igniter, path, contents))}

      Ritual.Overwrite.prompt?(igniter, label) ->
        source =
          igniter.rewrite
          |> Rewrite.source!(path)
          |> Igniter.update_source(igniter, :content, contents, by: :file_creator)

        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}

      true ->
        igniter
    end
  end
end
