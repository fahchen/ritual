defmodule Mix.Tasks.Ritual.Install.FormatTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Format

  describe "plain library" do
    test "leaves the default `inputs` intact" do
      igniter = test_project() |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      assert content =~
               ~s|inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]|

      refute content =~ "import_deps:"
      refute content =~ "plugins:"
      refute content =~ "subdirectories:"
      refute content =~ "export:"
    end

    test "is idempotent" do
      assert_idempotent(test_project())
    end
  end

  describe "Hex package" do
    test "does NOT auto-inject an export skeleton" do
      igniter = hex_package_project() |> Format.igniter()
      content = file_content(igniter, ".formatter.exs")

      refute content =~ "export:"
      refute content =~ "locals_without_parens:"
    end

    test "emits a notice instructing the author to add export: by hand" do
      igniter = hex_package_project() |> Format.igniter()

      assert Enum.any?(igniter.notices, fn notice ->
               notice =~ "Hex-publishable" and notice =~ "export:"
             end)
    end

    test "is idempotent" do
      assert_idempotent(hex_package_project())
    end
  end

  describe "Phoenix project" do
    test "adds the standard Phoenix import_deps in alphabetical order" do
      igniter = phoenix_project() |> Format.igniter()
      content = file_content(igniter, ".formatter.exs")

      assert content =~ "import_deps:"
      assert content =~ ":phoenix"
      assert content =~ ":ecto"
      assert content =~ ":ecto_sql"

      # Lock in alphabetical ordering so future changes to @phoenix_import_deps
      # do not silently flip diff-noise on user files.
      assert [_, ecto_pos, ecto_sql_pos, phoenix_pos | _] =
               Enum.map([":ecto", ":ecto", ":ecto_sql", ":phoenix"], fn token ->
                 :binary.match(content, token) |> elem(0)
               end)

      assert ecto_pos < ecto_sql_pos
      assert ecto_sql_pos < phoenix_pos
    end

    test "adds Phoenix.LiveView.HTMLFormatter as a plugin" do
      igniter = phoenix_project() |> Format.igniter()
      content = file_content(igniter, ".formatter.exs")

      assert content =~ "Phoenix.LiveView.HTMLFormatter"
      assert content =~ "plugins:"
    end

    test "is idempotent" do
      assert_idempotent(phoenix_project())
    end

    test "does not duplicate :phoenix when already imported" do
      igniter =
        phoenix_project(
          formatter: """
          [
            import_deps: [:phoenix],
            inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
          ]
          """
        )
        |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      occurrences =
        content
        |> String.split(":phoenix", trim: true)
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1
    end
  end

  describe "Phoenix + LiveView" do
    test "still adds Phoenix.LiveView.HTMLFormatter (LV plugin is what matters)" do
      igniter =
        phoenix_project(extra_deps: [{:phoenix_live_view, "~> 1.0"}])
        |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      assert content =~ "Phoenix.LiveView.HTMLFormatter"
    end
  end

  describe "umbrella project" do
    test "writes umbrella-shaped inputs and subdirectories" do
      igniter = umbrella_project() |> Format.igniter()
      content = file_content(igniter, ".formatter.exs")

      assert content =~ ~s|inputs: ["mix.exs", "config/*.exs"]|
      assert content =~ ~s|subdirectories: ["apps/*"]|
    end

    test "is idempotent" do
      assert_idempotent(umbrella_project())
    end
  end

  describe "umbrella + Phoenix" do
    test "stacks umbrella shape with Phoenix.LiveView.HTMLFormatter plugin" do
      igniter =
        umbrella_project(extra_deps: [{:phoenix, "~> 1.7"}])
        |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      assert content =~ ~s|subdirectories: ["apps/*"]|
      assert content =~ "Phoenix.LiveView.HTMLFormatter"
    end
  end

  describe "umbrella + Phoenix + Hex package (triple combination)" do
    test "stacks umbrella shape, Phoenix plugins, and the Hex notice" do
      igniter =
        umbrella_project(
          extra_deps: [{:phoenix, "~> 1.7"}],
          hex_package: true
        )
        |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      assert content =~ ~s|subdirectories: ["apps/*"]|
      assert content =~ "Phoenix.LiveView.HTMLFormatter"
      refute content =~ "export:"

      assert Enum.any?(igniter.notices, fn notice -> notice =~ "Hex-publishable" end)
    end
  end

  describe "umbrella with custom inputs" do
    test "preserves a hand-tuned `inputs:` value (not equal to the default)" do
      custom_inputs = ~s|["mix.exs", "config/*.exs", "priv/scripts/*.exs"]|

      igniter =
        umbrella_project(
          formatter: """
          [
            inputs: #{custom_inputs}
          ]
          """
        )
        |> Format.igniter()

      content = file_content(igniter, ".formatter.exs")

      assert content =~ custom_inputs
      assert content =~ ~s|subdirectories: ["apps/*"]|
    end
  end

  describe "malformed `.formatter.exs`" do
    test "emits a warning and does not crash when the file is not a keyword list" do
      igniter =
        umbrella_project(formatter: ~s|"not a keyword list"\n|)
        |> Format.igniter()

      assert Enum.any?(igniter.warnings, fn warning ->
               warning =~ "Could not update" or warning =~ ".formatter.exs"
             end)
    end
  end

  # Asserts that running the format task twice on the given project produces
  # the same `.formatter.exs` content as running it once. We can't use
  # `assert_unchanged/2` here because the rewrite source baseline is the
  # original file, not the post-first-run state.
  defp assert_idempotent(project) do
    after_first = project |> Format.igniter() |> file_content(".formatter.exs")

    after_second =
      project |> Format.igniter() |> Format.igniter() |> file_content(".formatter.exs")

    assert after_first == after_second, """
    Format task is not idempotent.

    After first run:

    #{after_first}

    After second run:

    #{after_second}
    """
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
            [licenses: ["MIT"], links: %{}]
          end

          defp deps, do: []
        end
        """
      }
    )
  end

  defp phoenix_project(opts \\ []) do
    extra_deps = Keyword.get(opts, :extra_deps, [])
    deps = [{:phoenix, "~> 1.7"} | extra_deps]

    deps_src =
      deps
      |> Enum.map(&Macro.to_string/1)
      |> Enum.join(",\n      ")

    files = %{
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

    files =
      case Keyword.get(opts, :formatter) do
        nil -> files
        contents -> Map.put(files, ".formatter.exs", contents)
      end

    test_project(app_name: :my_app, files: files)
  end

  defp umbrella_project(opts \\ []) do
    extra_deps = Keyword.get(opts, :extra_deps, [])
    hex_package? = Keyword.get(opts, :hex_package, false)

    deps_src =
      extra_deps
      |> Enum.map(&Macro.to_string/1)
      |> Enum.join(",\n      ")

    {package_in_project, package_def} =
      if hex_package? do
        {"package: package(),\n              ",
         "\n  defp package, do: [licenses: [\"MIT\"], links: %{}]\n"}
      else
        {"", ""}
      end

    files = %{
      "mix.exs" => """
      defmodule MyUmbrella.MixProject do
        use Mix.Project

        def project do
          [
            apps_path: "apps",
            #{package_in_project}version: "0.1.0",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end
      #{package_def}
        defp deps do
          [
            #{deps_src}
          ]
        end
      end
      """
    }

    files =
      case Keyword.get(opts, :formatter) do
        nil -> files
        contents -> Map.put(files, ".formatter.exs", contents)
      end

    test_project(app_name: :my_umbrella, files: files)
  end
end
