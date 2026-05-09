defmodule Mix.Tasks.Ritual.Install.DialyzerTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Dialyzer, as: DialyzerTask

  describe "plain library" do
    test "adds the dialyxir dependency to mix.exs" do
      igniter = test_project() |> DialyzerTask.igniter()

      content = file_content(igniter, "mix.exs")

      assert content =~ ":dialyxir"
      assert content =~ "~> 1.4"
      assert content =~ "only: [:dev, :test]"
      assert content =~ "runtime: false"
    end

    test "injects a `dialyzer:` keyword in `project/0` with PLT paths derived from `:app`" do
      igniter = test_project(app_name: :my_app) |> DialyzerTask.igniter()
      content = file_content(igniter, "mix.exs")

      assert content =~ "dialyzer:"
      assert content =~ ~s|plt_local_path: "priv/plts/my_app.plt"|
      assert content =~ ~s|plt_core_path: "priv/plts/core.plt"|
      assert content =~ "plt_add_apps: [:ex_unit, :mix]"
      assert content =~ ~s|ignore_warnings: ".dialyzer_ignore.exs"|
    end

    test "creates `.dialyzer_ignore.exs` with an empty list and helpful comments" do
      igniter = test_project() |> DialyzerTask.igniter()
      content = file_content(igniter, ".dialyzer_ignore.exs")

      # The file must evaluate to a list (Dialyzer reads it via Code.eval_file/1).
      {result, _bindings} = Code.eval_string(content)
      assert result == []

      # Comment surface so users know what to add.
      assert content =~ "Add false-positive Dialyzer warnings here"
    end

    test "is idempotent" do
      project = test_project(app_name: :my_app)

      after_first =
        project
        |> DialyzerTask.igniter()
        |> snapshot()

      after_second =
        project
        |> DialyzerTask.igniter()
        |> DialyzerTask.igniter()
        |> snapshot()

      assert after_first == after_second
    end
  end

  describe "umbrella project (no `:app` key)" do
    test "falls back to `priv/plts/project.plt` when `:app` is absent" do
      igniter = umbrella_project() |> DialyzerTask.igniter()
      content = file_content(igniter, "mix.exs")

      assert content =~ ~s|plt_local_path: "priv/plts/project.plt"|
      assert content =~ ~s|plt_core_path: "priv/plts/core.plt"|
    end
  end

  describe "preexisting `dialyzer:` keyword" do
    test "leaves an existing dialyzer block untouched" do
      igniter =
        project_with_existing_dialyzer()
        |> DialyzerTask.igniter()

      content = file_content(igniter, "mix.exs")

      # Sentinels from the hand-written block must survive verbatim — PLT
      # paths, plt_add_apps, AND a custom ignore_warnings value all stay.
      assert content =~ ~s|plt_local_path: "priv/plts/custom.plt"|
      assert content =~ "plt_add_apps: [:ex_unit, :mix, :phoenix_test]"
      assert content =~ ~s|ignore_warnings: "config/custom_ignore.exs"|

      # Exactly one `ignore_warnings:` survives — no second one was layered on.
      occurrences =
        content
        |> String.split("ignore_warnings:", trim: true)
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1
    end
  end

  describe "preexisting `:dialyxir` dep" do
    test "leaves an existing dialyxir declaration in place (does not duplicate)" do
      igniter =
        project_with_existing_dialyxir_dep()
        |> DialyzerTask.igniter()

      content = file_content(igniter, "mix.exs")

      occurrences =
        content
        |> String.split(":dialyxir,", trim: true)
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1
    end
  end

  describe "preexisting `.dialyzer_ignore.exs`" do
    test "does NOT overwrite an existing ignore file" do
      sentinel = "# user-authored ignore list — do not touch\n[~r/foo/]\n"

      igniter =
        test_project(files: %{".dialyzer_ignore.exs" => sentinel})
        |> DialyzerTask.igniter()

      assert file_content(igniter, ".dialyzer_ignore.exs") == sentinel
    end
  end

  describe "--force flag" do
    test "replaces an existing `dialyzer:` keyword with the canonical block" do
      igniter =
        project_with_existing_dialyzer()
        |> with_force_flag()
        |> DialyzerTask.igniter()

      content = file_content(igniter, "mix.exs")

      # Custom values from the fixture must be gone after the overwrite.
      refute content =~ ~s|plt_local_path: "priv/plts/custom.plt"|
      refute content =~ ":phoenix_test"
      refute content =~ ~s|ignore_warnings: "config/custom_ignore.exs"|

      # Canonical block has replaced them — PLT path derives from `:app`.
      assert content =~ ~s|plt_local_path: "priv/plts/my_app.plt"|
      assert content =~ ~s|plt_core_path: "priv/plts/core.plt"|
      assert content =~ "plt_add_apps: [:ex_unit, :mix]"
      assert content =~ ~s|ignore_warnings: ".dialyzer_ignore.exs"|
    end

    test "regenerates `.dialyzer_ignore.exs` from the template" do
      sentinel = "# user-authored ignore list — do not touch\n[~r/foo/]\n"

      igniter =
        test_project(files: %{".dialyzer_ignore.exs" => sentinel})
        |> with_force_flag()
        |> DialyzerTask.igniter()

      content = file_content(igniter, ".dialyzer_ignore.exs")

      refute content == sentinel
      assert content =~ "Add false-positive Dialyzer warnings here"
      assert {[], _bindings} = Code.eval_string(content)
    end
  end

  # --- helpers ---

  defp snapshot(igniter) do
    {
      file_content(igniter, "mix.exs"),
      file_content(igniter, ".dialyzer_ignore.exs")
    }
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

  defp project_with_existing_dialyzer do
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
              dialyzer: [
                plt_local_path: "priv/plts/custom.plt",
                plt_core_path: "priv/plts/core.plt",
                plt_add_apps: [:ex_unit, :mix, :phoenix_test],
                ignore_warnings: "config/custom_ignore.exs"
              ],
              deps: deps()
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

  defp project_with_existing_dialyxir_dep do
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
              {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
            ]
          end
        end
        """
      }
    )
  end
end
