defmodule Mix.Tasks.Ritual.Install.Publish do
  @shortdoc "Write a GitHub Actions workflow that publishes the package to Hex on `v*` tags."

  @moduledoc """
  #{@shortdoc}

  Writes `.github/workflows/publish.yml`. The workflow is triggered by
  pushes of tags matching `v*` and runs `mix hex.publish --yes --replace`
  with `HEX_API_KEY` plumbed in from a repository secret.

  Only fires for Hex packages (`Ritual.Detect.hex_package?/1`); for non-Hex
  projects the task adds a notice and is a no-op.

  ## Self-contained setup

  The workflow inlines its setup-beam steps rather than referencing
  `./.github/workflows/actions/setup`. The composite action is only
  written by `mix ritual.install.ci` for non-Hex projects (mise style),
  and Hex packages get the setup-beam matrix CI instead — there is no
  composite action available to depend on. Inlining keeps the publish
  workflow runnable on its own and avoids a chicken-and-egg dependency
  between the two installers.

  The Elixir/OTP versions match the lint row of the setup-beam CI matrix
  so the publishing toolchain matches the gating CI run.

  ## Idempotent

  Existing `publish.yml` files are preserved verbatim — re-running the
  task will not clobber a hand-edited workflow.
  """

  use Igniter.Mix.Task

  import Ritual.IgniterCompat, only: [include_or_create_plain_file: 3]

  alias Ritual.Ci
  alias Ritual.Detect

  @publish_workflow ".github/workflows/publish.yml"

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.publish",
      schema: [],
      defaults: [],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    if Detect.hex_package?(igniter) do
      include_or_create_plain_file(igniter, @publish_workflow, Ci.publish_workflow())
    else
      Igniter.add_notice(
        igniter,
        "ritual.install.publish: not a Hex package (no `package/0` in mix.exs) — skipping publish workflow."
      )
    end
  end
end
