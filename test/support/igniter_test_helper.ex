defmodule Ritual.IgniterTestHelper do
  @moduledoc """
  Test helpers wrapping `Igniter.Test` for the Ritual installer tasks.

  Centralises the small set of conveniences Ritual's installer tests reach
  for so individual test files can stay focused on assertions rather than
  scaffolding.
  """

  import ExUnit.Assertions

  @doc """
  Builds an in-memory test project, deferring to `Igniter.Test.test_project/1`.

  Accepts the same options as the underlying helper (`:files`, `:app_name`,
  ...). Returns an `Igniter.t()` ready to receive task invocations via
  `Igniter.compose_task/3`.
  """
  @spec test_project(keyword()) :: Igniter.t()
  def test_project(opts \\ []), do: Igniter.Test.test_project(opts)

  @doc """
  Returns the simulated content of `path` after applying `igniter`.

  Useful when an assertion needs to inspect the final file contents instead
  of comparing patches. Prefer `Igniter.Test.assert_has_patch/3` and
  `Igniter.Test.assert_creates/3` when patch- or creation-level assertions
  suffice.

  Note: this helper reaches into `igniter.rewrite` (a `Rewrite` struct), which
  is an Igniter implementation detail rather than a stable public API. If
  Igniter renames or restructures that field, update this single helper
  rather than every test site.
  """
  @spec file_content(Igniter.t(), Path.t()) :: String.t()
  def file_content(%Igniter{} = igniter, path) do
    case Rewrite.source(igniter.rewrite, path) do
      {:ok, source} ->
        Rewrite.Source.get(source, :content)

      :error ->
        flunk("""
        Expected the igniter to contain a source for #{inspect(path)}, but it does not.

        Known sources:

        #{igniter.rewrite |> Rewrite.sources() |> Enum.map_join("\n", &"  * #{&1.path}")}
        """)
    end
  end
end
