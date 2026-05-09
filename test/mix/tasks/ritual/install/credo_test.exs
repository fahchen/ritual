defmodule Mix.Tasks.Ritual.Install.CredoTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Credo, as: CredoTask

  describe "plain library" do
    test "adds the credo dependency to mix.exs" do
      igniter = test_project() |> CredoTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ ":credo"
      assert content =~ "~> 1.7"
      assert content =~ "only: [:dev, :test]"
      assert content =~ "runtime: false"
    end

    test "creates `.credo.exs` with default `files.included` (no apps/* paths)" do
      igniter = test_project() |> CredoTask.igniter()

      content = file_content(igniter, ".credo.exs")

      assert content =~ ~s|"lib/"|
      assert content =~ ~s|"test/"|
      refute content =~ "apps/*"
    end

    test "creates `.credo.exs` with the common subset of checks" do
      igniter = test_project() |> CredoTask.igniter()
      content = file_content(igniter, ".credo.exs")

      # Sentinel checks pulled from the common subset across reference projects.
      assert content =~ "Credo.Check.Consistency.UnusedVariableNames"
      assert content =~ "force: :meaningful"
      assert content =~ "Credo.Check.Design.AliasUsage"
      assert content =~ "if_nested_deeper_than: 3"
      assert content =~ "Credo.Check.Readability.MaxLineLength"
      assert content =~ "max_length: 120"
      assert content =~ "Credo.Check.Readability.NestedFunctionCalls"
      assert content =~ "min_pipeline_length: 3"
      assert content =~ "Credo.Check.Readability.Specs"
      assert content =~ "exclude_test_files"

      # Sentinel disabled entries — including the four opt-in checks that
      # ship in `disabled` so users see them and can promote to `enabled` at
      # will (mirrors grephql's `.credo.exs`).
      assert content =~ "Credo.Check.Readability.AliasAs"
      assert content =~ "Credo.Check.Readability.BlockPipe"
      assert content =~ "Credo.Check.Readability.SingleFunctionToBlockPipe"
      assert content =~ "Credo.Check.Readability.StrictModuleLayout"
      assert content =~ "Credo.Check.Readability.SeparateAliasRequire"
      assert content =~ "Credo.Check.Refactor.ABCSize"
      assert content =~ "Credo.Check.Refactor.ModuleDependencies"
      assert content =~ "Credo.Check.Refactor.VariableRebinding"
      assert content =~ "Credo.Check.Warning.LeakyEnvironment"
    end

    test "the generated `.credo.exs` evaluates to a valid keyword config" do
      igniter = test_project() |> CredoTask.igniter()
      content = file_content(igniter, ".credo.exs")

      # If this raises, the template emitted invalid Elixir — which would
      # silently break consumers when they run `mix credo`.
      {result, _bindings} = Code.eval_string(content)

      assert is_map(result)
      assert [config] = result.configs
      assert config.name == "default"
    end

    test "is idempotent" do
      project = test_project()

      after_first =
        project
        |> CredoTask.igniter()
        |> then(&{file_content(&1, "mix.exs"), file_content(&1, ".credo.exs")})

      after_second =
        project
        |> CredoTask.igniter()
        |> CredoTask.igniter()
        |> then(&{file_content(&1, "mix.exs"), file_content(&1, ".credo.exs")})

      assert after_first == after_second
    end
  end

  describe "umbrella project" do
    test "creates `.credo.exs` that includes apps/* paths and Phoenix web/ paths" do
      igniter = umbrella_project() |> CredoTask.igniter()
      content = file_content(igniter, ".credo.exs")

      assert content =~ ~s|"apps/*/lib/"|
      assert content =~ ~s|"apps/*/test/"|
      assert content =~ ~s|"apps/*/src/"|
      assert content =~ ~s|"apps/*/web/"|
      assert content =~ ~s|"web/"|
      assert content =~ "node_modules"
    end

    test "the generated umbrella `.credo.exs` evaluates to a valid config" do
      igniter = umbrella_project() |> CredoTask.igniter()
      content = file_content(igniter, ".credo.exs")

      {result, _bindings} = Code.eval_string(content)

      assert is_map(result)
      assert [config] = result.configs
      assert config.name == "default"
      assert "apps/*/lib/" in config.files.included
    end

    test "is idempotent" do
      project = umbrella_project()

      after_first =
        project |> CredoTask.igniter() |> file_content(".credo.exs")

      after_second =
        project
        |> CredoTask.igniter()
        |> CredoTask.igniter()
        |> file_content(".credo.exs")

      assert after_first == after_second
    end
  end

  describe "preexisting `.credo.exs`" do
    test "does NOT overwrite an existing `.credo.exs`" do
      sentinel = "# user-authored credo config — do not touch\n[]\n"

      igniter =
        test_project(files: %{".credo.exs" => sentinel})
        |> CredoTask.igniter()

      assert file_content(igniter, ".credo.exs") == sentinel
    end
  end

  describe "--force flag" do
    test "regenerates `.credo.exs` from the template, clobbering an existing file" do
      sentinel = "# user-authored credo config — do not touch\n[]\n"

      igniter =
        test_project(files: %{".credo.exs" => sentinel})
        |> with_force_flag()
        |> CredoTask.igniter()

      content = file_content(igniter, ".credo.exs")

      refute content == sentinel
      assert content =~ "checks:"
      assert content =~ "Credo.Check.Readability.MaxLineLength"
    end
  end

  describe "preexisting `:credo` dep" do
    test "leaves an existing credo declaration in place (does not duplicate)" do
      igniter =
        project_with_existing_credo_dep()
        |> CredoTask.igniter()

      content = file_content(igniter, "mix.exs")

      occurrences =
        content
        |> String.split(":credo,", trim: true)
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1
    end
  end

  # --- fixtures ---

  defp umbrella_project do
    test_project(
      app_name: :my_umbrella,
      files: %{
        "mix.exs" => """
        defmodule MyUmbrella.MixProject do
          use Mix.Project

          def project do
            [
              apps_path: "apps",
              version: "0.1.0",
              start_permanent: Mix.env() == :prod,
              deps: deps()
            ]
          end

          defp deps do
            []
          end
        end
        """
      }
    )
  end

  defp project_with_existing_credo_dep do
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
              {:credo, "~> 1.6", only: [:dev], runtime: false}
            ]
          end
        end
        """
      }
    )
  end
end
