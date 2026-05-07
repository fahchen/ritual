defmodule Mix.Tasks.Ritual.Install.PrecommitTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Precommit, as: PrecommitTask

  describe "plain library (no credo, no dialyxir)" do
    test "adds a precommit alias with only the always-on steps" do
      igniter = library_project() |> PrecommitTask.igniter()
      content = file_content(igniter, "mix.exs")

      assert content =~ "precommit:"
      assert content =~ ~s|"compile --warnings-as-errors"|
      assert content =~ ~s|"deps.unlock --unused"|
      assert content =~ ~s|"format"|
      assert content =~ ~s|"test"|

      refute content =~ "credo --strict"
      refute content =~ ~s|"dialyzer"|
    end

    test "adds `cli/0` with `preferred_envs: [precommit: :test]`" do
      igniter = library_project() |> PrecommitTask.igniter()
      content = file_content(igniter, "mix.exs")

      assert content =~ "def cli"
      assert content =~ "preferred_envs:"
      assert content =~ "precommit: :test"
    end

    test "is idempotent" do
      project = library_project()

      after_first = project |> PrecommitTask.igniter() |> file_content("mix.exs")

      after_second =
        project
        |> PrecommitTask.igniter()
        |> PrecommitTask.igniter()
        |> file_content("mix.exs")

      assert after_first == after_second
    end
  end

  describe "project with `:credo` declared" do
    test "includes `credo --strict` step" do
      igniter =
        library_project(extra_deps: [{:credo, "~> 1.7", only: [:dev, :test], runtime: false}])
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ ~s|"credo --strict"|
      refute content =~ ~s|"dialyzer"|
    end
  end

  describe "project with `:dialyxir` declared" do
    test "includes `dialyzer` step" do
      igniter =
        library_project(extra_deps: [{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}])
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ ~s|"dialyzer"|
      refute content =~ ~s|"credo --strict"|
    end
  end

  describe "project with both `:credo` and `:dialyxir`" do
    test "includes both steps in canonical order" do
      igniter =
        library_project(
          extra_deps: [
            {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
            {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
          ]
        )
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ ~s|"credo --strict"|
      assert content =~ ~s|"dialyzer"|

      # Canonical order: compile -> deps.unlock -> format -> credo -> dialyzer -> test.
      compile_pos = :binary.match(content, "compile --warnings-as-errors") |> elem(0)
      unlock_pos = :binary.match(content, "deps.unlock --unused") |> elem(0)
      format_pos = :binary.match(content, ~s|"format"|) |> elem(0)
      credo_pos = :binary.match(content, "credo --strict") |> elem(0)
      dialyzer_pos = :binary.match(content, ~s|"dialyzer"|) |> elem(0)
      test_pos = :binary.match(content, ~s|"test"|) |> elem(0)

      assert compile_pos < unlock_pos
      assert unlock_pos < format_pos
      assert format_pos < credo_pos
      assert credo_pos < dialyzer_pos
      assert dialyzer_pos < test_pos
    end
  end

  describe "preexisting `precommit` alias" do
    test "does NOT modify the existing alias" do
      igniter =
        project_with_existing_precommit()
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      # The hand-written precommit only runs `format` and `test`. If we replaced
      # it, the canonical entries (compile --warnings-as-errors etc.) would
      # appear inside the alias.
      assert content =~ ~s|precommit: ["format", "test"]|
      refute content =~ "compile --warnings-as-errors"
    end

    test "emits a notice describing the canonical precommit alias" do
      igniter =
        project_with_existing_precommit()
        |> PrecommitTask.igniter()

      assert Enum.any?(igniter.notices, fn notice ->
               notice =~ "precommit" and notice =~ "canonical"
             end)
    end

    test "does NOT emit the notice when the alias was newly created" do
      igniter = library_project() |> PrecommitTask.igniter()

      refute Enum.any?(igniter.notices, fn notice ->
               notice =~ "precommit" and notice =~ "canonical"
             end)
    end
  end

  describe "preexisting `cli/0` with other `preferred_envs`" do
    test "merges `:precommit` alongside existing entries (preserves them)" do
      igniter =
        project_with_existing_cli()
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ "precommit: :test"
      # Pre-existing entry must survive verbatim.
      assert content =~ "other_task: :test"
    end

    test "leaves an existing `precommit: :dev` mapping alone" do
      igniter =
        project_with_existing_precommit_env(:dev)
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ "precommit: :dev"
      refute content =~ "precommit: :test"
    end
  end

  describe "empty `aliases/0`" do
    test "adds the precommit alias when aliases/0 exists but is empty" do
      igniter =
        project_with_empty_aliases()
        |> PrecommitTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ "precommit:"
      assert content =~ ~s|"format"|
      assert content =~ ~s|"test"|
    end
  end

  describe "idempotency across all shapes" do
    test "running twice on a project with credo and dialyxir is identical to running once" do
      project =
        library_project(
          extra_deps: [
            {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
            {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
          ]
        )

      after_first = project |> PrecommitTask.igniter() |> file_content("mix.exs")

      after_second =
        project
        |> PrecommitTask.igniter()
        |> PrecommitTask.igniter()
        |> file_content("mix.exs")

      assert after_first == after_second
    end
  end

  # --- fixtures ---

  defp library_project(opts \\ []) do
    extra_deps = Keyword.get(opts, :extra_deps, [])

    deps_src =
      extra_deps
      |> Enum.map(&dep_to_source/1)
      |> Enum.join(",\n      ")

    test_project(
      app_name: :my_app,
      files: %{
        "mix.exs" => """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: deps()
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp deps do
            [
              #{deps_src}
            ]
          end
        end
        """
      }
    )
  end

  defp project_with_existing_precommit do
    test_project(
      app_name: :my_app,
      files: %{
        "mix.exs" => """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: deps(),
              aliases: aliases()
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp deps do
            []
          end

          defp aliases do
            [
              precommit: ["format", "test"]
            ]
          end
        end
        """
      }
    )
  end

  defp project_with_empty_aliases do
    test_project(
      app_name: :my_app,
      files: %{
        "mix.exs" => """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: deps(),
              aliases: aliases()
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp deps do
            []
          end

          defp aliases do
            []
          end
        end
        """
      }
    )
  end

  defp project_with_existing_cli do
    test_project(
      app_name: :my_app,
      files: %{
        "mix.exs" => """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: deps()
            ]
          end

          def cli do
            [
              preferred_envs: [other_task: :test]
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp deps do
            []
          end
        end
        """
      }
    )
  end

  # `Macro.to_string/1` chokes on raw Elixir tuples like
  # `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` because it
  # expects an AST. Render the dep as a Mix-style tuple literal directly.
  defp dep_to_source({name, requirement, opts}) do
    "{#{inspect(name)}, #{inspect(requirement)}, #{Enum.map_join(opts, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)}}"
  end

  defp dep_to_source({name, requirement}) do
    "{#{inspect(name)}, #{inspect(requirement)}}"
  end

  defp project_with_existing_precommit_env(env) do
    env_str = inspect(env)

    test_project(
      app_name: :my_app,
      files: %{
        "mix.exs" => """
        defmodule MyApp.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_app,
              version: "0.1.0",
              elixir: "~> 1.17",
              deps: deps()
            ]
          end

          def cli do
            [
              preferred_envs: [precommit: #{env_str}]
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp deps do
            []
          end
        end
        """
      }
    )
  end
end
