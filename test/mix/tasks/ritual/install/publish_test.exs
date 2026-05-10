defmodule Mix.Tasks.Ritual.Install.PublishTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Publish, as: PublishTask

  @publish_workflow ".github/workflows/publish.yml"

  describe "Hex package" do
    test "creates `.github/workflows/publish.yml` with publish sentinels" do
      igniter = hex_package_project() |> PublishTask.igniter()
      content = file_content(igniter, @publish_workflow)

      # Workflow header.
      assert content =~ "name: Publish"

      # Trigger: tag push matching `v*`.
      assert content =~ "tags:"
      assert content =~ "v*"

      # Inlined setup-beam steps (Option B — self-contained, no composite ref).
      assert content =~ "actions/checkout@v5"
      assert content =~ "erlef/setup-beam@v1"
      assert content =~ "elixir-version:"
      assert content =~ "otp-version:"

      # Hex publish flow. `mix hex.build` runs before `mix hex.publish` so
      # manifest errors surface before authentication.
      assert content =~ "mix deps.get"
      assert content =~ "mix hex.build"
      assert content =~ "mix hex.publish --yes"

      # `--replace` is intentionally NOT the default — overwriting a
      # published tarball would silently change downstream lockfile bytes.
      refute content =~ "--replace"

      # Hex API key plumbed via repo secret.
      assert content =~ "HEX_API_KEY"
      assert content =~ "secrets.HEX_API_KEY"

      # No composite action reference — publish workflow is self-contained.
      refute content =~ "./.github/workflows/actions/setup"

      # Document order: build before publish.
      build_pos = :binary.match(content, "mix hex.build") |> elem(0)
      publish_pos = :binary.match(content, "mix hex.publish") |> elem(0)
      assert build_pos < publish_pos
    end

    test "is idempotent" do
      project = hex_package_project()

      after_first =
        project
        |> PublishTask.igniter()
        |> file_content(@publish_workflow)

      after_second =
        project
        |> PublishTask.igniter()
        |> PublishTask.igniter()
        |> file_content(@publish_workflow)

      assert after_first == after_second
    end

    test "does NOT overwrite an existing publish.yml" do
      sentinel = "# user-authored publish workflow — do not touch\nname: hand-rolled\n"

      igniter =
        test_project(
          app_name: :my_lib,
          files:
            Map.merge(hex_package_files(), %{
              @publish_workflow => sentinel
            })
        )
        |> PublishTask.igniter()

      assert file_content(igniter, @publish_workflow) == sentinel
    end
  end

  describe "non-Hex project" do
    test "does NOT write publish.yml" do
      igniter = test_project() |> PublishTask.igniter()

      refute Map.has_key?(igniter.rewrite.sources, @publish_workflow)
    end

    test "emits a notice explaining the skip" do
      igniter = test_project() |> PublishTask.igniter()

      assert Enum.any?(igniter.notices, &(&1 =~ "not a Hex package"))
    end
  end

  describe "--force flag" do
    test "overwrites an existing publish.yml" do
      sentinel = "# stale publish workflow\nname: hand-rolled\n"

      igniter =
        test_project(
          app_name: :my_lib,
          files: Map.merge(hex_package_files(), %{@publish_workflow => sentinel})
        )
        |> with_force_flag()
        |> PublishTask.igniter()

      content = file_content(igniter, @publish_workflow)

      refute content == sentinel
      assert content =~ "name: Publish"
      assert content =~ "mix hex.publish --yes"
    end
  end

  # --- fixtures ---

  defp hex_package_project do
    test_project(app_name: :my_lib, files: hex_package_files())
  end

  defp hex_package_files do
    %{
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
  end
end
