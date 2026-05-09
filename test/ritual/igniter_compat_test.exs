defmodule Ritual.IgniterCompatTest do
  use ExUnit.Case, async: true

  import Ritual.IgniterTestHelper

  alias Ritual.IgniterCompat

  describe "include_or_create_plain_file/3" do
    test "marks the freshly created source as updated so Igniter persists it" do
      igniter =
        test_project()
        |> IgniterCompat.include_or_create_plain_file("mise.toml", "[tools]\nx = 1\n")

      source = Map.fetch!(igniter.rewrite.sources, "mise.toml")

      # Sources made via `Rewrite.Source.from_string/2` alone have
      # `updated?: false` and Igniter's apply phase silently skips them
      # (regression observed in #commit-000100b — generated files vanished
      # in real runs even though in-memory tests passed).
      assert Rewrite.Source.updated?(source)
    end
  end

  describe "ensure_gitignore_lines/2" do
    test "appends missing lines to an existing .gitignore" do
      igniter =
        test_project(files: %{".gitignore" => "/_build/\n/deps/\n"})
        |> IgniterCompat.ensure_gitignore_lines([
          "/priv/plts/*.plt",
          "/priv/plts/*.plt.hash"
        ])

      content = file_content(igniter, ".gitignore")
      assert content =~ "/priv/plts/*.plt\n"
      assert content =~ "/priv/plts/*.plt.hash\n"
      # Existing lines preserved verbatim, original ordering kept.
      assert String.starts_with?(content, "/_build/\n/deps/\n")
    end

    test "is idempotent — re-running does not append duplicates" do
      project = test_project(files: %{".gitignore" => "/_build/\n"})
      lines = ["/priv/plts/*.plt"]

      after_first =
        project
        |> IgniterCompat.ensure_gitignore_lines(lines)
        |> file_content(".gitignore")

      after_second =
        project
        |> IgniterCompat.ensure_gitignore_lines(lines)
        |> IgniterCompat.ensure_gitignore_lines(lines)
        |> file_content(".gitignore")

      assert after_first == after_second
    end

    test "ensures a trailing newline when the original file lacked one" do
      igniter =
        test_project(files: %{".gitignore" => "/_build/"})
        |> IgniterCompat.ensure_gitignore_lines(["/priv/plts/*.plt"])

      content = file_content(igniter, ".gitignore")
      assert content == "/_build/\n/priv/plts/*.plt\n"
    end
  end

  describe "write_or_create_plain_file/4" do
    test "marks the freshly created source as updated" do
      igniter =
        test_project()
        |> IgniterCompat.write_or_create_plain_file(
          "mise.toml",
          "[tools]\nx = 1\n",
          "mise.toml"
        )

      source = Map.fetch!(igniter.rewrite.sources, "mise.toml")
      assert Rewrite.Source.updated?(source)
    end
  end
end
