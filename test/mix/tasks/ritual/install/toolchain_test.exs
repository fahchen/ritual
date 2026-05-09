defmodule Mix.Tasks.Ritual.Install.ToolchainTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Mix.Tasks.Ritual.Install.Toolchain, as: ToolchainTask
  alias Ritual.Toolchain

  describe "default flag (mise)" do
    test "creates `mise.toml` with a `[tools]` table containing erlang and elixir" do
      igniter = test_project() |> ToolchainTask.igniter()
      content = file_content(igniter, "mise.toml")

      assert content =~ "[tools]"
      assert content =~ ~s|erlang = "|
      assert content =~ ~s|elixir = "|
    end

    test "uses versions reported by `Ritual.Toolchain` helpers" do
      igniter = test_project() |> ToolchainTask.igniter()
      content = file_content(igniter, "mise.toml")

      assert content =~ ~s|erlang = "#{Toolchain.current_erlang_version()}"|
      assert content =~ ~s|elixir = "#{Toolchain.current_elixir_version()}"|
    end

    test "does not create `.tool-versions` in the default mode" do
      igniter = test_project() |> ToolchainTask.igniter()

      refute Map.has_key?(igniter.rewrite.sources, ".tool-versions")
    end

    test "does NOT overwrite an existing `mise.toml`" do
      sentinel = """
      [tools]
      erlang = "27.0"
      elixir = "1.17.0-otp-27"

      [tasks.hello]
      run = "echo hi"
      """

      igniter =
        test_project(files: %{"mise.toml" => sentinel})
        |> ToolchainTask.igniter()

      assert file_content(igniter, "mise.toml") == sentinel
    end

    test "is idempotent" do
      project = test_project()

      after_first = project |> ToolchainTask.igniter() |> file_content("mise.toml")

      after_second =
        project
        |> ToolchainTask.igniter()
        |> ToolchainTask.igniter()
        |> file_content("mise.toml")

      assert after_first == after_second
    end
  end

  describe "--tool-versions flag" do
    test "creates `.tool-versions` with two space-separated lines" do
      igniter = test_project() |> with_tool_versions_flag() |> ToolchainTask.igniter()
      content = file_content(igniter, ".tool-versions")

      assert content =~ "erlang #{Toolchain.current_erlang_version()}"
      assert content =~ "elixir #{Toolchain.current_elixir_version()}"
      refute content =~ "[tools]"
    end

    test "does not create `mise.toml` when the flag is set" do
      igniter = test_project() |> with_tool_versions_flag() |> ToolchainTask.igniter()

      refute Map.has_key?(igniter.rewrite.sources, "mise.toml")
    end

    test "does NOT overwrite an existing `.tool-versions`" do
      sentinel = "erlang 27.0\nelixir 1.17.0-otp-27\nnodejs 20\n"

      igniter =
        test_project(files: %{".tool-versions" => sentinel})
        |> with_tool_versions_flag()
        |> ToolchainTask.igniter()

      assert file_content(igniter, ".tool-versions") == sentinel
    end

    test "is idempotent" do
      project = test_project()

      after_first =
        project
        |> with_tool_versions_flag()
        |> ToolchainTask.igniter()
        |> file_content(".tool-versions")

      after_second =
        project
        |> with_tool_versions_flag()
        |> ToolchainTask.igniter()
        |> with_tool_versions_flag()
        |> ToolchainTask.igniter()
        |> file_content(".tool-versions")

      assert after_first == after_second
    end
  end

  describe "--force flag" do
    test "overwrites an existing `mise.toml` with the freshly rendered content" do
      sentinel = "# stale custom mise.toml\n[tools]\nerlang = \"26.0\"\n"

      igniter =
        test_project(files: %{"mise.toml" => sentinel})
        |> with_force_flag()
        |> ToolchainTask.igniter()

      content = file_content(igniter, "mise.toml")

      refute content == sentinel
      assert content =~ ~s|erlang = "#{Toolchain.current_erlang_version()}"|
      assert content =~ ~s|elixir = "#{Toolchain.current_elixir_version()}"|
    end

    test "overwrites an existing `.tool-versions` when paired with --tool-versions" do
      sentinel = "erlang 26.0\nelixir 1.16.0-otp-26\n"

      igniter =
        test_project(files: %{".tool-versions" => sentinel})
        |> with_tool_versions_flag()
        |> with_force_flag()
        |> ToolchainTask.igniter()

      content = file_content(igniter, ".tool-versions")

      refute content == sentinel
      assert content =~ "erlang #{Toolchain.current_erlang_version()}"
      assert content =~ "elixir #{Toolchain.current_elixir_version()}"
    end
  end

  # Pre-populates the `--tool-versions` flag in `igniter.args.options`. When
  # the task is invoked directly (as opposed to via `Mix.Task.run/2` or
  # `Igniter.compose_task/3`), no argv parsing happens, so flags must be
  # injected manually. Build on top of the default `Args` struct so any future
  # fields stay populated.
  defp with_tool_versions_flag(igniter) do
    args = igniter.args || %Igniter.Mix.Task.Args{}
    options = Keyword.put(args.options, :tool_versions, true)
    %{igniter | args: %{args | options: options}}
  end
end
