defmodule Ritual.DetectTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Ritual.Detect

  describe "umbrella?/1" do
    test "returns false for a default (non-umbrella) project" do
      refute Detect.umbrella?(test_project())
    end

    test "returns true when project/0 sets apps_path" do
      igniter =
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

      assert Detect.umbrella?(igniter)
    end
  end

  describe "phoenix?/1" do
    test "returns false when :phoenix is not in deps" do
      refute Detect.phoenix?(test_project())
    end

    test "returns true when :phoenix is declared in deps/0" do
      igniter = project_with_deps([{:phoenix, "~> 1.7"}])
      assert Detect.phoenix?(igniter)
    end

    test "returns false when an unrelated dep is present" do
      igniter = project_with_deps([{:jason, "~> 1.4"}])
      refute Detect.phoenix?(igniter)
    end
  end

  describe "phoenix_live_view?/1" do
    test "returns false on a default project" do
      refute Detect.phoenix_live_view?(test_project())
    end

    test "returns true when :phoenix_live_view is in deps" do
      igniter = project_with_deps([{:phoenix_live_view, "~> 1.0"}])
      assert Detect.phoenix_live_view?(igniter)
    end

    test "returns false when only :phoenix is present" do
      igniter = project_with_deps([{:phoenix, "~> 1.7"}])
      refute Detect.phoenix_live_view?(igniter)
    end

    test "returns true alongside phoenix? when both deps are declared" do
      igniter = project_with_deps([{:phoenix, "~> 1.7"}, {:phoenix_live_view, "~> 1.0"}])
      assert Detect.phoenix?(igniter)
      assert Detect.phoenix_live_view?(igniter)
    end
  end

  describe "hex_package?/1" do
    test "returns false for a bare project without package/0" do
      refute Detect.hex_package?(test_project())
    end

    test "returns true when a defp package/0 clause is defined" do
      igniter =
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
                [licenses: ["MIT"], links: %{}]
              end

              defp deps, do: []
            end
            """
          }
        )

      assert Detect.hex_package?(igniter)
    end

    test "returns true when a public def package/0 clause is defined" do
      igniter =
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
                  package: package(),
                  deps: deps()
                ]
              end

              def application, do: [extra_applications: [:logger]]

              def package do
                [licenses: ["MIT"], links: %{}]
              end

              defp deps, do: []
            end
            """
          }
        )

      assert Detect.hex_package?(igniter)
    end

    test "returns false for an arity-1 package/1 clause (documents the contract)" do
      igniter =
        test_project(
          app_name: :my_lib,
          files: %{
            "mix.exs" => """
            defmodule MyLib.MixProject do
              use Mix.Project

              def project, do: [app: :my_lib, version: "0.1.0", deps: []]

              defp package(opts \\\\ []) do
                [licenses: ["MIT"], links: opts]
              end
            end
            """
          }
        )

      # Hex's package/0 callback is arity-0; this guards against accidental
      # detection of unrelated arity-1 helpers that happen to be named package.
      refute Detect.hex_package?(igniter)
    end
  end

  describe "app_name/1" do
    test "returns {:ok, atom} from project/0 in a regular project" do
      assert Detect.app_name(test_project()) == {:ok, :test}
    end

    test "respects a custom :app_name option" do
      assert Detect.app_name(test_project(app_name: :my_app)) == {:ok, :my_app}
    end

    test "returns :error for an umbrella mix.exs that omits :app" do
      igniter =
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

              defp deps, do: []
            end
            """
          }
        )

      assert Detect.app_name(igniter) == :error
    end

    test "returns {:ok, atom} for an umbrella mix.exs that does set :app" do
      igniter =
        test_project(
          app_name: :my_umbrella,
          files: %{
            "mix.exs" => """
            defmodule MyUmbrella.MixProject do
              use Mix.Project

              def project do
                [
                  app: :my_umbrella,
                  apps_path: "apps",
                  version: "0.1.0",
                  deps: []
                ]
              end
            end
            """
          }
        )

      assert Detect.app_name(igniter) == {:ok, :my_umbrella}
    end
  end

  describe "do: shorthand support" do
    test "handles `def project, do: [...]` shorthand the same as a do/end block" do
      igniter =
        test_project(
          app_name: :tiny,
          files: %{
            "mix.exs" => """
            defmodule Tiny.MixProject do
              use Mix.Project

              def project,
                do: [app: :tiny, apps_path: "apps", version: "0.1.0", deps: []]
            end
            """
          }
        )

      assert Detect.umbrella?(igniter)
      assert Detect.app_name(igniter) == {:ok, :tiny}
    end
  end

  defp project_with_deps(deps) do
    deps_src =
      deps
      |> Enum.map(&Macro.to_string/1)
      |> Enum.join(",\n      ")

    test_project(
      app_name: :sample,
      files: %{
        "mix.exs" => """
        defmodule Sample.MixProject do
          use Mix.Project

          def project do
            [
              app: :sample,
              version: "0.1.0",
              elixir: "~> 1.17",
              start_permanent: Mix.env() == :prod,
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
end
