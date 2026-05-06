defmodule Ritual.Detect do
  @moduledoc """
  Stateless inspection of an `Igniter.t()` to report a project's shape.

  Every Ritual installer (format, credo, dialyzer, ci, publish) branches on
  the predicates in this module. All functions are pure on the in-memory
  Igniter (its `Rewrite` is the source of truth) and never read from disk.

  ## Caveats

    * Reads of `mix.exs` go through `Rewrite.Source.get(source, :quoted)`,
      which is an Igniter implementation detail. If Igniter changes its
      internal Rewrite version or source representation this breaks at
      runtime; the access is centralised in `mix_zipper/1` so callers do not
      need to care.

    * If a caller has already queued a write to `mix.exs` (e.g. via
      `Igniter.update_elixir_file/3`) on the same `Igniter.t()`, the detection
      reads the **pre-modification** AST, not the pending edit. Run detection
      *before* mutating `mix.exs`.

    * `package/0` detection only matches arity 0; `def package(opts \\\\ [])`
      (arity 1) returns `false`. Hex's convention is arity 0, so this is
      intentional.
  """

  alias Igniter.Code.Common
  alias Igniter.Code.Function, as: IFunction
  alias Igniter.Code.Keyword, as: IKeyword
  alias Igniter.Code.List, as: IList

  @doc """
  Returns `true` if `mix.exs` declares `apps_path:` inside `project/0`,
  which is the canonical signal of an umbrella project.
  """
  @spec umbrella?(Igniter.t()) :: boolean()
  def umbrella?(igniter) do
    case project_keyword_zipper(igniter) do
      {:ok, zipper} ->
        match?({:ok, _}, IKeyword.get_key(zipper, :apps_path))

      :error ->
        false
    end
  end

  @doc "Returns `true` if `mix.exs` declares a `:phoenix` dependency."
  @spec phoenix?(Igniter.t()) :: boolean()
  def phoenix?(igniter), do: Igniter.Project.Deps.has_dep?(igniter, :phoenix)

  @doc "Returns `true` if `mix.exs` declares a `:phoenix_live_view` dependency."
  @spec phoenix_live_view?(Igniter.t()) :: boolean()
  def phoenix_live_view?(igniter),
    do: Igniter.Project.Deps.has_dep?(igniter, :phoenix_live_view)

  @doc """
  Returns `true` if `mix.exs` defines a `package/0` clause (public or
  private), the conventional marker for a Hex-publishable project.
  """
  @spec hex_package?(Igniter.t()) :: boolean()
  def hex_package?(igniter) do
    case mix_zipper(igniter) do
      {:ok, zipper} ->
        match?({:ok, _}, IFunction.move_to_def(zipper, :package, 0)) or
          match?({:ok, _}, IFunction.move_to_defp(zipper, :package, 0))

      :error ->
        false
    end
  end

  @doc """
  Returns `{:ok, atom}` with the application name from `app:` in `project/0`,
  or `:error` when the key is absent or unreadable.

  Umbrella `mix.exs` files commonly omit `:app`; this function returns
  `:error` in that case rather than raising. Wrapping in a tagged tuple lets
  callers compose with `with` and avoids `nil`-propagation guards.
  """
  @spec app_name(Igniter.t()) :: {:ok, atom()} | :error
  def app_name(igniter) do
    with {:ok, zipper} <- project_keyword_zipper(igniter),
         {:ok, value} <- IKeyword.get_key(zipper, :app),
         {:ok, atom} when is_atom(atom) <- Common.expand_literal(value) do
      {:ok, atom}
    else
      _ -> :error
    end
  end

  # --- internal helpers ---

  # Returns a zipper at the top of mix.exs (after including it in the rewrite).
  defp mix_zipper(igniter) do
    igniter = Igniter.include_existing_file(igniter, "mix.exs")

    case Rewrite.source(igniter.rewrite, "mix.exs") do
      {:ok, source} ->
        {:ok,
         source
         |> Rewrite.Source.get(:quoted)
         |> Sourceror.Zipper.zip()}

      :error ->
        :error
    end
  end

  # Navigates to the keyword list returned by `project/0`.
  defp project_keyword_zipper(igniter) do
    with {:ok, zipper} <- mix_zipper(igniter),
         {:ok, zipper} <- IFunction.move_to_def(zipper, :project, 0) do
      keyword_list_zipper(zipper)
    end
  end

  defp keyword_list_zipper(zipper) do
    zipper = Common.rightmost(zipper)

    if IList.list?(zipper) do
      {:ok, zipper}
    else
      :error
    end
  end
end
