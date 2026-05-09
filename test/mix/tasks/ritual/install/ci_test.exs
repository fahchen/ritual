defmodule Mix.Tasks.Ritual.Install.CiTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Ci, as: CiTask

  @ci_workflow ".github/workflows/ci.yml"
  @setup_action ".github/workflows/actions/setup/action.yml"

  describe "plain library (mise style)" do
    test "creates `.github/workflows/ci.yml` with mise-style sentinels" do
      igniter = test_project() |> CiTask.igniter()
      content = file_content(igniter, @ci_workflow)

      # Workflow header + triggers.
      assert content =~ "name: CI"
      assert content =~ "branches: [main]"
      assert content =~ "MIX_ENV: test"

      # Single job uses the local composite setup action — the mise-style hallmark.
      assert content =~ "uses: ./.github/workflows/actions/setup"

      # Sequential lint + test pipeline.
      assert content =~ "mix deps.unlock --check-unused"
      assert content =~ "mix format --check-formatted"
      assert content =~ "mix compile --warnings-as-errors"
      assert content =~ "mix credo --strict"
      assert content =~ "mix dialyzer"
      assert content =~ "mix test"

      # PLT cache references composite action outputs.
      assert content =~ "steps.setup.outputs.erlang-version"
      assert content =~ "steps.setup.outputs.elixir-version"

      # No matrix — that is the setup-beam shape.
      refute content =~ "matrix:"
      refute content =~ "erlef/setup-beam"
    end

    test "creates `.github/workflows/actions/setup/action.yml` with mise sentinels" do
      igniter = test_project() |> CiTask.igniter()
      content = file_content(igniter, @setup_action)

      assert content =~ "using: composite"
      assert content =~ "jdx/mise-action"
      assert content =~ "mix local.hex --force"
      assert content =~ "mix local.rebar --force"

      # Outputs feed `${{ steps.setup.outputs.* }}` references in ci.yml.
      assert content =~ "erlang-version:"
      assert content =~ "elixir-version:"

      # Mix dependency cache is the setup action's responsibility.
      assert content =~ "actions/cache"
      assert content =~ "mix deps.get"
      assert content =~ "mix deps.compile"
    end

    test "is idempotent" do
      project = test_project()

      after_first =
        project
        |> CiTask.igniter()
        |> snapshot()

      after_second =
        project
        |> CiTask.igniter()
        |> CiTask.igniter()
        |> snapshot()

      assert after_first == after_second
    end
  end

  describe "Hex package (setup-beam matrix style)" do
    test "creates `.github/workflows/ci.yml` with a setup-beam matrix" do
      igniter = hex_package_project() |> CiTask.igniter()
      content = file_content(igniter, @ci_workflow)

      assert content =~ "name: CI"
      assert content =~ "erlef/setup-beam"
      assert content =~ "matrix:"
      assert content =~ "include:"
      assert content =~ "elixir:"
      assert content =~ "otp:"

      # The lint row gates lint/format/credo/dialyzer steps.
      assert content =~ "lint: lint"
      assert content =~ "if: ${{ matrix.lint }}"

      # mise composite action MUST NOT be referenced from the matrix workflow.
      refute content =~ "./.github/workflows/actions/setup"
      refute content =~ "jdx/mise-action"
    end

    test "does NOT create the mise composite setup action for Hex packages" do
      igniter = hex_package_project() |> CiTask.igniter()

      refute Map.has_key?(igniter.rewrite.sources, @setup_action)
    end

    test "is idempotent" do
      project = hex_package_project()

      after_first = project |> CiTask.igniter() |> hex_snapshot()

      after_second =
        project
        |> CiTask.igniter()
        |> CiTask.igniter()
        |> hex_snapshot()

      assert after_first == after_second
    end
  end

  describe "preexisting workflow files" do
    test "does NOT overwrite an existing `.github/workflows/ci.yml`" do
      sentinel = "# user-authored CI — do not touch\nname: hand-rolled\n"

      igniter =
        test_project(files: %{@ci_workflow => sentinel})
        |> CiTask.igniter()

      assert file_content(igniter, @ci_workflow) == sentinel
    end

    test "does NOT overwrite an existing setup composite action" do
      sentinel = "# user-authored composite action — do not touch\nname: hand-rolled\n"

      igniter =
        test_project(files: %{@setup_action => sentinel})
        |> CiTask.igniter()

      assert file_content(igniter, @setup_action) == sentinel
    end
  end

  describe "--force flag" do
    test "overwrites an existing `ci.yml` (mise style)" do
      sentinel = "# stale CI workflow\nname: hand-rolled\n"

      igniter =
        test_project(files: %{@ci_workflow => sentinel})
        |> with_force_flag()
        |> CiTask.igniter()

      content = file_content(igniter, @ci_workflow)

      refute content == sentinel
      assert content =~ "name: CI"
      assert content =~ "uses: ./.github/workflows/actions/setup"
    end

    test "overwrites an existing composite setup action" do
      sentinel = "# stale composite action\nname: hand-rolled\n"

      igniter =
        test_project(files: %{@setup_action => sentinel})
        |> with_force_flag()
        |> CiTask.igniter()

      content = file_content(igniter, @setup_action)

      refute content == sentinel
      assert content =~ "using: composite"
      assert content =~ "jdx/mise-action"
    end
  end

  # --- helpers ---

  defp snapshot(igniter) do
    {file_content(igniter, @ci_workflow), file_content(igniter, @setup_action)}
  end

  # Hex packages must NOT receive the composite setup action; the snapshot
  # captures both the workflow content and the absence of the action so a
  # regression that started writing one would flip the second-run diff.
  defp hex_snapshot(igniter) do
    {file_content(igniter, @ci_workflow), Map.has_key?(igniter.rewrite.sources, @setup_action)}
  end

  # --- fixtures ---

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
