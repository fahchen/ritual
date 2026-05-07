defmodule Ritual.ToolchainTest do
  use ExUnit.Case, async: true

  alias Ritual.Toolchain

  describe "current_elixir_version/0" do
    test "returns Elixir patch version with `-otp-MAJOR` suffix" do
      version = Toolchain.current_elixir_version()

      assert is_binary(version)
      # Pattern: 1.19.5-otp-28 — three numeric segments + literal `-otp-` + integer.
      assert version =~ ~r/^\d+\.\d+\.\d+-otp-\d+$/
      assert version =~ System.version()
      assert version =~ "-otp-#{System.otp_release()}"
    end
  end

  describe "current_erlang_version/0" do
    test "returns a non-empty version string" do
      version = Toolchain.current_erlang_version()

      assert is_binary(version)
      refute version == ""
      # Either a full version (28.3) or the bare OTP major (28). Both must
      # start with the OTP major so mise/asdf can resolve.
      assert version =~ ~r/^\d+(\.\d+){0,2}$/
      assert String.starts_with?(version, System.otp_release())
    end
  end

  describe "mise_toml/0" do
    test "renders a `[tools]` table with erlang and elixir entries" do
      content = Toolchain.mise_toml()

      assert content =~ "[tools]"
      assert content =~ ~s|erlang = "#{Toolchain.current_erlang_version()}"|
      assert content =~ ~s|elixir = "#{Toolchain.current_elixir_version()}"|
      # Final newline so editors don't re-add one on save.
      assert String.ends_with?(content, "\n")
    end
  end

  describe "tool_versions/0" do
    test "renders space-separated `tool version` lines" do
      content = Toolchain.tool_versions()

      assert content =~ "erlang #{Toolchain.current_erlang_version()}"
      assert content =~ "elixir #{Toolchain.current_elixir_version()}"
      assert String.ends_with?(content, "\n")
      # Two lines, no [tools] header.
      refute content =~ "[tools]"
    end
  end
end
