defmodule Mix.Tasks.Ritual.BootstrapTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Bootstrap, as: BootstrapTask
  alias Ritual.Toolchain

  @ci_workflow ".github/workflows/ci.yml"
  @publish_workflow ".github/workflows/publish.yml"

  # All sub-task names in the canonical order. Mirrors the list in
  # `Mix.Tasks.Ritual.Bootstrap.info/2` (`:composes`) so that adding/removing
  # an installer breaks the test in an obvious place.
  @all_subtasks [
    "ritual.install.format",
    "ritual.install.toolchain",
    "ritual.install.credo",
    "ritual.install.dialyzer",
    "ritual.install.precommit",
    "ritual.install.ci",
    "ritual.install.publish"
  ]

  describe "--yes flag" do
    test "composes every sub-installer on a Hex package (full pipeline)" do
      igniter =
        hex_package_project()
        |> with_yes_flag()
        |> BootstrapTask.igniter()

      # Each sub-task is identified by a distinctive sentinel produced by
      # that installer. If any sub-task was skipped, its sentinel disappears
      # from the rewrite and the assertion fails loudly.
      assert file_content(igniter, ".formatter.exs") =~ "inputs:"
      assert file_content(igniter, "mise.toml") =~ "[tools]"
      assert file_content(igniter, ".credo.exs") =~ "checks:"

      mix_exs = file_content(igniter, "mix.exs")
      assert mix_exs =~ "dialyzer:"
      assert mix_exs =~ "precommit:"

      assert file_content(igniter, @ci_workflow) =~ "name: CI"
      assert file_content(igniter, @publish_workflow) =~ "name: Publish"
    end

    test "composes every sub-installer on a plain library (no publish file)" do
      # `--yes` still *runs* the publish sub-task; that sub-task is itself a
      # no-op on non-Hex projects (it only emits a notice). So the publish
      # workflow file is still absent on a plain library.
      igniter =
        plain_project()
        |> with_yes_flag()
        |> BootstrapTask.igniter()

      assert file_content(igniter, ".formatter.exs") =~ "inputs:"
      assert file_content(igniter, "mise.toml") =~ "[tools]"
      assert file_content(igniter, ".credo.exs") =~ "checks:"
      assert file_content(igniter, "mix.exs") =~ "dialyzer:"
      assert file_content(igniter, @ci_workflow) =~ "name: CI"

      refute Map.has_key?(igniter.rewrite.sources, @publish_workflow)
      assert Enum.any?(igniter.notices, &(&1 =~ "not a Hex package"))
    end
  end

  describe "selective installation via :bootstrap_selection assigns hook" do
    test "skips a sub-task when its entry is false" do
      igniter =
        plain_project()
        |> Igniter.assign(:bootstrap_selection, all_selected_except("ritual.install.credo"))
        |> BootstrapTask.igniter()

      # Format / toolchain / dialyzer / precommit / ci all ran.
      assert file_content(igniter, ".formatter.exs") =~ "inputs:"
      assert file_content(igniter, "mise.toml") =~ "[tools]"
      assert file_content(igniter, "mix.exs") =~ "dialyzer:"
      assert file_content(igniter, "mix.exs") =~ "precommit:"
      assert file_content(igniter, @ci_workflow) =~ "name: CI"

      # Credo did NOT run.
      refute Map.has_key?(igniter.rewrite.sources, ".credo.exs")
    end

    test "skipping dialyzer keeps `mix dialyzer` out of the precommit alias" do
      # Exercises the cross-task interaction: precommit's smart-skip logic
      # (Phase 7) reads `:dialyxir` from the in-memory mix.exs, which the
      # dialyzer sub-task would have added. Skipping dialyzer leaves
      # `:dialyxir` absent, so precommit must omit `mix dialyzer` from the
      # alias steps.
      igniter =
        plain_project()
        |> Igniter.assign(:bootstrap_selection, all_selected_except("ritual.install.dialyzer"))
        |> BootstrapTask.igniter()

      mix_exs = file_content(igniter, "mix.exs")

      assert mix_exs =~ "precommit:"
      refute mix_exs =~ "dialyxir"
      refute mix_exs =~ ~s|"dialyzer"|
    end

    test "selecting only one sub-task runs only that one" do
      igniter =
        plain_project()
        |> Igniter.assign(
          :bootstrap_selection,
          @all_subtasks
          |> Enum.map(&{&1, false})
          |> Map.new()
          |> Map.put("ritual.install.format", true)
        )
        |> BootstrapTask.igniter()

      assert file_content(igniter, ".formatter.exs") =~ "inputs:"

      # No other installer ran.
      refute Map.has_key?(igniter.rewrite.sources, "mise.toml")
      refute Map.has_key?(igniter.rewrite.sources, ".credo.exs")
      refute Map.has_key?(igniter.rewrite.sources, ".dialyzer_ignore.exs")
      refute Map.has_key?(igniter.rewrite.sources, @ci_workflow)
    end
  end

  describe "publish-prompt default" do
    test "defaults to true when the project is a Hex package" do
      # Pre-populate the selection map for everything *except* publish so that
      # the bootstrap task has to fall back to the per-prompt default for
      # publish. On a Hex package that default is true → publish file exists.
      igniter =
        hex_package_project()
        |> Igniter.assign(:bootstrap_selection, all_selected_except_publish())
        |> BootstrapTask.igniter()

      assert file_content(igniter, @publish_workflow) =~ "name: Publish"
    end

    test "defaults to false when the project is NOT a Hex package" do
      igniter =
        plain_project()
        |> Igniter.assign(:bootstrap_selection, all_selected_except_publish())
        |> BootstrapTask.igniter()

      # Plain library + default-N publish prompt → publish sub-task is
      # skipped entirely, so there is no notice from it either.
      refute Map.has_key?(igniter.rewrite.sources, @publish_workflow)
      refute Enum.any?(igniter.notices, &(&1 =~ "not a Hex package"))
    end
  end

  describe "--tool-versions flag" do
    test "forwards through to the toolchain sub-installer" do
      igniter =
        plain_project()
        |> with_yes_flag()
        |> with_tool_versions_flag()
        |> BootstrapTask.igniter()

      content = file_content(igniter, ".tool-versions")

      assert content =~ "erlang #{Toolchain.current_erlang_version()}"
      assert content =~ "elixir #{Toolchain.current_elixir_version()}"
      refute Map.has_key?(igniter.rewrite.sources, "mise.toml")
    end
  end

  # --- helpers ---

  # Builds a selection map keyed by sub-task name, with every sub-task set
  # to true except the named one (which is set to false).
  defp all_selected_except(skip_task) do
    @all_subtasks
    |> Enum.map(&{&1, &1 != skip_task})
    |> Map.new()
  end

  # Builds a selection map that enables every sub-task EXCEPT publish, which
  # is left unset so the bootstrap task falls back to its per-prompt default.
  defp all_selected_except_publish do
    @all_subtasks
    |> Enum.reject(&(&1 == "ritual.install.publish"))
    |> Enum.map(&{&1, true})
    |> Map.new()
  end

  defp with_yes_flag(igniter) do
    args = igniter.args || %Igniter.Mix.Task.Args{}
    options = Keyword.put(args.options, :yes, true)
    argv_flags = ["--yes" | args.argv_flags]
    %{igniter | args: %{args | options: options, argv_flags: argv_flags}}
  end

  defp with_tool_versions_flag(igniter) do
    args = igniter.args || %Igniter.Mix.Task.Args{}
    options = Keyword.put(args.options, :tool_versions, true)
    argv_flags = ["--tool-versions" | args.argv_flags]
    %{igniter | args: %{args | options: options, argv_flags: argv_flags}}
  end

  # --- fixtures ---

  defp plain_project do
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
            []
          end
        end
        """
      }
    )
  end

  defp hex_package_project do
    test_project(
      app_name: :my_lib,
      files: %{
        "mix.exs" => """
        defmodule MyLib.MixProject do
          use Mix.Project

          def project do
            [
              app: :my_lib,
              version: "0.1.0",
              elixir: "~> 1.17",
              package: package(),
              deps: deps()
            ]
          end

          def application, do: [extra_applications: [:logger]]

          defp package do
            [
              licenses: ["MIT"],
              links: %{}
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
end
