defmodule Ritual.Toolchain do
  @moduledoc """
  Helpers for detecting the running Erlang/OTP and Elixir versions and
  rendering them into the two file formats supported by
  `mix ritual.install.toolchain`:

    * mise (default) — TOML `[tools]` table written to `mise.toml`
    * asdf — space-separated `tool version` lines written to `.tool-versions`

  ## Version detection strategy

    * **Elixir**: `System.version()` returns the patch-level version
      (e.g. `"1.19.5"`). The mise/asdf-style suffix `-otp-<major>` is
      appended using `System.otp_release()`, yielding strings like
      `"1.19.5-otp-28"`.

    * **Erlang/OTP**: the canonical full version (e.g. `"28.3"`) lives in
      `<code_root>/releases/<otp_release>/OTP_VERSION`. We read that file
      directly because it is the same source mise/asdf themselves consult,
      and falls back to the bare OTP major (`"28"`) if the file is unreadable
      (e.g. a stripped runtime). The bare major is still resolvable by
      mise/asdf, just less precise.
  """

  @doc """
  Returns the current Elixir version with an `-otp-<major>` suffix.

  ## Examples

      iex> Ritual.Toolchain.current_elixir_version() =~ ~r/^\\d+\\.\\d+\\.\\d+-otp-\\d+$/
      true
  """
  @spec current_elixir_version() :: String.t()
  def current_elixir_version do
    "#{System.version()}-otp-#{System.otp_release()}"
  end

  @doc """
  Returns the current Erlang/OTP version.

  Reads `<code_root>/releases/<otp_release>/OTP_VERSION` for the full
  triplet (e.g. `"28.3"`); if the file cannot be read, falls back to the
  OTP major from `System.otp_release/0` (e.g. `"28"`). Both forms are
  acceptable to mise and asdf.
  """
  @spec current_erlang_version() :: String.t()
  def current_erlang_version do
    otp_release = System.otp_release()
    path = Path.join([:code.root_dir() |> to_string(), "releases", otp_release, "OTP_VERSION"])

    case File.read(path) do
      {:ok, contents} -> String.trim(contents)
      {:error, _} -> otp_release
    end
  end

  @doc """
  Renders a `mise.toml` file body pinning erlang and elixir under `[tools]`.
  """
  @spec mise_toml() :: String.t()
  def mise_toml do
    """
    [tools]
    erlang = "#{current_erlang_version()}"
    elixir = "#{current_elixir_version()}"
    """
  end

  @doc """
  Renders a `.tool-versions` file body pinning erlang and elixir.
  """
  @spec tool_versions() :: String.t()
  def tool_versions do
    """
    erlang #{current_erlang_version()}
    elixir #{current_elixir_version()}
    """
  end
end
