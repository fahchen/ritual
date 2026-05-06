defmodule Ritual.Formatter do
  @moduledoc """
  Helpers for shaping a project's `.formatter.exs` based on detected
  characteristics (umbrella, Phoenix).

  All functions are pure transformations on an `Igniter.t()` and are
  designed to be idempotent: invoking them repeatedly produces the same
  `.formatter.exs` regardless of how many times the task runs.

  The Mix task `mix ritual.install.format` composes these helpers; tests
  should normally drive the task instead of calling these helpers directly.

  ## Hex packages

  No automatic `export:` injection: the key is only meaningful when a
  library defines custom locals or formatter plugins, and shipping an empty
  `export: [locals_without_parens: [], plugins: []]` skeleton just teaches
  users to ignore it. The task instead emits a notice on Hex packages so
  authors can fill it in deliberately.
  """

  alias Igniter.Code.Common
  alias Igniter.Code.Keyword, as: IKeyword
  alias Igniter.Code.List, as: IList
  alias Igniter.Project.Formatter, as: IFormatter

  @default_inputs ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]

  @default_formatter """
  # Used by "mix format"
  [
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  # Reversed so prepend-reduce in apply_phoenix/1 lands on alphabetical order
  # in the resulting import_deps list (Igniter's import_dep/2 prepends).
  @phoenix_import_deps [:phoenix, :ecto_sql, :ecto]

  @doc """
  Ensures `.formatter.exs` exists at the project root.

  Creates the default Mix-generated `.formatter.exs` (with the standard
  `inputs:`) when no file is present. A no-op when the file already exists.
  """
  @spec ensure_present(Igniter.t()) :: Igniter.t()
  def ensure_present(igniter) do
    Igniter.include_or_create_file(igniter, ".formatter.exs", @default_formatter)
  end

  @doc """
  Rewrites `.formatter.exs` for an umbrella project.

  Sets `inputs: ["mix.exs", "config/*.exs"]` (only when the existing value is
  the default Mix-generated `inputs:` — user customisations are preserved)
  and ensures `subdirectories: ["apps/*"]` is present.
  """
  @spec apply_umbrella(Igniter.t()) :: Igniter.t()
  def apply_umbrella(igniter) do
    igniter
    |> ensure_present()
    |> Igniter.update_elixir_file(".formatter.exs", fn zipper ->
      with {:ok, zipper} <- top_keyword_list(zipper),
           {:ok, zipper} <-
             replace_default_keyword(
               zipper,
               :inputs,
               @default_inputs,
               ["mix.exs", "config/*.exs"]
             ),
           {:ok, zipper} <- ensure_keyword(zipper, :subdirectories, ["apps/*"]) do
        {:ok, zipper}
      else
        :error ->
          {:warning,
           "Could not update `.formatter.exs` for umbrella shape; please update manually."}
      end
    end)
  end

  @doc """
  Adds the Phoenix-specific entries to `.formatter.exs`.

  Imports `:ecto`, `:ecto_sql`, and `:phoenix` formatter rules and adds
  `Phoenix.LiveView.HTMLFormatter` as a plugin. Each underlying call goes
  through the existing Igniter helpers, which already deduplicate, so this
  function is safe to call repeatedly.
  """
  @spec apply_phoenix(Igniter.t()) :: Igniter.t()
  def apply_phoenix(igniter) do
    igniter
    |> ensure_present()
    |> then(fn igniter ->
      Enum.reduce(@phoenix_import_deps, igniter, &IFormatter.import_dep(&2, &1))
    end)
    |> IFormatter.add_formatter_plugin(Phoenix.LiveView.HTMLFormatter)
  end

  # --- internal helpers ---

  # Navigates to the top-level keyword list of `.formatter.exs`.
  defp top_keyword_list(zipper) do
    zipper = zipper |> Common.maybe_move_to_single_child_block() |> Common.rightmost()

    if IList.list?(zipper) do
      {:ok, zipper}
    else
      :error
    end
  end

  # Replaces `key` with `new_value` only when the existing value matches
  # `default`. Preserves user customisations; idempotent because a second run
  # finds `new_value` (not `default`) and skips.
  defp replace_default_keyword(zipper, key, default, new_value) do
    IKeyword.set_keyword_key(zipper, key, new_value, fn existing_zipper ->
      if Common.nodes_equal?(existing_zipper, default) do
        {:ok, Common.replace_code(existing_zipper, new_value)}
      else
        {:ok, existing_zipper}
      end
    end)
    |> case do
      {:ok, zipper} -> {:ok, zipper}
      _ -> :error
    end
  end

  # Sets `key` to `value` only if the key is absent. Existing keys keep
  # their current value (preserves user customisations).
  defp ensure_keyword(zipper, key, value) do
    IKeyword.set_keyword_key(zipper, key, value, fn existing -> {:ok, existing} end)
    |> case do
      {:ok, zipper} -> {:ok, zipper}
      _ -> :error
    end
  end
end
