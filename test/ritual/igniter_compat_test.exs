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
