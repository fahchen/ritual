defmodule Mix.Tasks.Ritual.InstallTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install, as: InstallTask
  alias Ritual.Toolchain

  @ci_workflow ".github/workflows/ci.yml"
  @publish_workflow ".github/workflows/publish.yml"
  @setup_action ".github/workflows/actions/setup/action.yml"

  describe "plain library" do
    test "runs every always-on sub-installer" do
      igniter = plain_project() |> InstallTask.igniter()

      # Format — `.formatter.exs` is touched (Igniter.Project.Formatter
      # always queues at least an `import_deps:`/`inputs:` keyword).
      formatter = file_content(igniter, ".formatter.exs")
      assert formatter =~ "inputs:"

      # Toolchain — default mode writes mise.toml.
      mise = file_content(igniter, "mise.toml")
      assert mise =~ "[tools]"
      assert mise =~ ~s|elixir = "|

      # Credo — config file written.
      credo = file_content(igniter, ".credo.exs")
      assert credo =~ "%{"
      assert credo =~ "checks:"

      # Dialyzer — `dialyzer:` keyword in mix.exs + ignore file.
      mix_exs = file_content(igniter, "mix.exs")
      assert mix_exs =~ "dialyzer:"
      ignore = file_content(igniter, ".dialyzer_ignore.exs")
      assert ignore =~ "[]"

      # Precommit — alias added to mix.exs.
      assert mix_exs =~ "precommit:"
      assert mix_exs =~ ~s|"compile --warnings-as-errors"|

      # CI — mise-style workflow + composite setup action (plain library).
      ci = file_content(igniter, @ci_workflow)
      assert ci =~ "name: CI"
      assert ci =~ "uses: ./.github/workflows/actions/setup"
      assert file_content(igniter, @setup_action) =~ "using: composite"
    end

    test "does NOT create the publish workflow" do
      igniter = plain_project() |> InstallTask.igniter()

      refute Map.has_key?(igniter.rewrite.sources, @publish_workflow)
    end

    test "publish sub-task emits a notice explaining the skip" do
      igniter = plain_project() |> InstallTask.igniter()

      assert Enum.any?(igniter.notices, &(&1 =~ "not a Hex package"))
    end

    test "is idempotent" do
      project = plain_project()

      after_first = project |> InstallTask.igniter() |> snapshot()

      after_second =
        project
        |> InstallTask.igniter()
        |> InstallTask.igniter()
        |> snapshot()

      assert after_first == after_second
    end
  end

  describe "Hex package" do
    test "runs every always-on sub-installer plus publish" do
      igniter = hex_package_project() |> InstallTask.igniter()

      # Spot-check the same always-on sentinels.
      assert file_content(igniter, ".formatter.exs") =~ "inputs:"
      assert file_content(igniter, "mise.toml") =~ "[tools]"
      assert file_content(igniter, ".credo.exs") =~ "checks:"

      mix_exs = file_content(igniter, "mix.exs")
      assert mix_exs =~ "dialyzer:"
      assert mix_exs =~ "precommit:"

      # Hex packages get the setup-beam matrix CI, NOT the mise composite.
      ci = file_content(igniter, @ci_workflow)
      assert ci =~ "erlef/setup-beam"
      assert ci =~ "matrix:"
      refute Map.has_key?(igniter.rewrite.sources, @setup_action)

      # Publish workflow IS created for Hex packages.
      publish = file_content(igniter, @publish_workflow)
      assert publish =~ "name: Publish"
      assert publish =~ "mix hex.publish --yes"
    end

    test "format installer surfaces the Hex export notice" do
      igniter = hex_package_project() |> InstallTask.igniter()

      assert Enum.any?(igniter.notices, &(&1 =~ "Hex-publishable project"))
    end

    test "is idempotent" do
      project = hex_package_project()

      after_first = project |> InstallTask.igniter() |> hex_snapshot()

      after_second =
        project
        |> InstallTask.igniter()
        |> InstallTask.igniter()
        |> hex_snapshot()

      assert after_first == after_second
    end
  end

  describe "--tool-versions flag" do
    test "writes `.tool-versions` instead of `mise.toml` for the toolchain step" do
      igniter =
        plain_project()
        |> with_tool_versions_flag()
        |> InstallTask.igniter()

      content = file_content(igniter, ".tool-versions")

      assert content =~ "erlang #{Toolchain.current_erlang_version()}"
      assert content =~ "elixir #{Toolchain.current_elixir_version()}"
      refute Map.has_key?(igniter.rewrite.sources, "mise.toml")
    end

    test "still runs the other always-on installers" do
      igniter =
        plain_project()
        |> with_tool_versions_flag()
        |> InstallTask.igniter()

      assert file_content(igniter, ".formatter.exs") =~ "inputs:"
      assert file_content(igniter, ".credo.exs") =~ "checks:"
      assert file_content(igniter, @ci_workflow) =~ "name: CI"
    end
  end

  # --- helpers ---

  # Captures a deterministic fingerprint of every file the aggregator might
  # touch on a plain library so the idempotency test fails loudly if any
  # sub-task starts producing different content on a re-run.
  defp snapshot(igniter) do
    %{
      formatter: file_content(igniter, ".formatter.exs"),
      mise: file_content(igniter, "mise.toml"),
      credo: file_content(igniter, ".credo.exs"),
      mix_exs: file_content(igniter, "mix.exs"),
      ignore: file_content(igniter, ".dialyzer_ignore.exs"),
      ci: file_content(igniter, @ci_workflow),
      setup_action: file_content(igniter, @setup_action),
      publish_present?: Map.has_key?(igniter.rewrite.sources, @publish_workflow)
    }
  end

  defp hex_snapshot(igniter) do
    %{
      formatter: file_content(igniter, ".formatter.exs"),
      mise: file_content(igniter, "mise.toml"),
      credo: file_content(igniter, ".credo.exs"),
      mix_exs: file_content(igniter, "mix.exs"),
      ignore: file_content(igniter, ".dialyzer_ignore.exs"),
      ci: file_content(igniter, @ci_workflow),
      publish: file_content(igniter, @publish_workflow),
      setup_action_present?: Map.has_key?(igniter.rewrite.sources, @setup_action)
    }
  end

  # See toolchain_test.exs for the rationale — when invoking `igniter/1`
  # directly we have to populate `args.options` manually.
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
