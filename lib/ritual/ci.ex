defmodule Ritual.Ci do
  @moduledoc """
  Renders the GitHub Actions workflow files written by
  `mix ritual.install.ci`.

  Two shapes are supported:

    * **mise** (default) — a single-job `ci.yml` plus a composite setup
      action at `.github/workflows/actions/setup/action.yml`. Tool versions
      come from `mise.toml` / `.tool-versions` via `jdx/mise-action`.

    * **setup-beam matrix** — a multi-version `ci.yml` driven by
      `erlef/setup-beam` and a `matrix:` over Elixir/OTP pairs. One row is
      flagged `lint: lint` and runs format/credo/dialyzer/test; the remaining
      rows run only `mix test`. Used for Hex packages, which need to verify
      compatibility against multiple Elixir/OTP combinations.

  All bodies are static text — there are no runtime interpolations, so they
  ship as module attributes rather than EEx templates. GitHub Actions
  expression literals (`${{ ... }}`) survive verbatim because EEx never sees
  the strings.

  ## Setup-beam matrix

  The matrix targets the latest stable Elixir on the latest stable OTP plus
  two prior majors. Older majors are intentionally omitted — Hex packages
  that need a longer support window can edit the workflow by hand.

  The lint row's Elixir/OTP pair is also used by the publish workflow so the
  publishing toolchain matches the gating CI run. Both literals are kept in
  one place via the `@lint_elixir` / `@lint_otp` module attributes.
  """

  @lint_elixir "1.19.5"
  @lint_otp "28.3"

  @mise_ci ~S"""
  name: CI

  on:
    push:
      branches: [main]
    pull_request:
      branches: [main]

  env:
    MIX_ENV: test

  jobs:
    test:
      name: CI
      runs-on: ubuntu-latest

      steps:
        - name: Checkout
          uses: actions/checkout@v5

        - name: Setup environment
          id: setup
          uses: ./.github/workflows/actions/setup

        - name: Check unused dependencies
          run: mix deps.unlock --check-unused

        - name: Check formatting
          run: mix format --check-formatted

        - name: Compile with warnings as errors
          run: mix compile --warnings-as-errors

        - name: Credo
          run: mix credo --strict

        - name: Restore PLT cache
          id: plt-cache
          uses: actions/cache@v5
          with:
            path: priv/plts
            key: plt-${{ runner.os }}-${{ steps.setup.outputs.erlang-version }}-${{ steps.setup.outputs.elixir-version }}-${{ hashFiles('**/mix.lock') }}
            restore-keys: |
              plt-${{ runner.os }}-${{ steps.setup.outputs.erlang-version }}-${{ steps.setup.outputs.elixir-version }}-

        - name: Create PLTs
          if: steps.plt-cache.outputs.cache-hit != 'true'
          run: mix dialyzer --plt

        - name: Dialyzer
          run: mix dialyzer

        - name: Run tests
          run: mix test
  """

  @mise_setup_action ~S"""
  name: Setup Development Environment
  description: Install mise tools and restore dependency caches

  outputs:
    erlang-version:
      description: "Erlang/OTP version"
      value: ${{ steps.tool-versions.outputs.erlang }}
    elixir-version:
      description: "Elixir version"
      value: ${{ steps.tool-versions.outputs.elixir }}

  runs:
    using: composite
    steps:
      - name: Install tools via mise
        uses: jdx/mise-action@v4
        with:
          install: true
          cache: true

      - name: Output tool versions
        id: tool-versions
        shell: bash
        # Read .tool-versions when present (asdf format); fall back to
        # `mise current` for projects pinned via mise.toml only.
        run: |
          if [[ -f .tool-versions ]]; then
            while IFS=' ' read -r tool version; do
              [[ -z "$tool" || "$tool" =~ ^# ]] && continue
              echo "$tool=$version" >> $GITHUB_OUTPUT
            done < .tool-versions
          else
            echo "erlang=$(mise current erlang)" >> $GITHUB_OUTPUT
            echo "elixir=$(mise current elixir)" >> $GITHUB_OUTPUT
          fi

      - name: Install Hex package manager
        shell: bash
        run: |
          mix local.hex --force
          mix local.rebar --force

      - name: Restore Mix dependencies
        id: mix-cache
        uses: actions/cache@v5
        with:
          path: |
            deps
            _build
          key: mix-${{ runner.os }}-${{ steps.tool-versions.outputs.erlang }}-${{ steps.tool-versions.outputs.elixir }}-${{ env.MIX_ENV || 'dev' }}-${{ hashFiles('**/mix.lock') }}
          restore-keys: |
            mix-${{ runner.os }}-${{ steps.tool-versions.outputs.erlang }}-${{ steps.tool-versions.outputs.elixir }}-${{ env.MIX_ENV || 'dev' }}-

      - name: Install Mix dependencies
        if: steps.mix-cache.outputs.cache-hit != 'true'
        shell: bash
        run: mix deps.get

      - name: Compile Mix dependencies
        if: steps.mix-cache.outputs.cache-hit != 'true'
        shell: bash
        run: mix deps.compile
  """

  @setup_beam_ci ~s"""
  name: CI

  on:
    push:
      branches: [main]
    pull_request:
      branches: [main]

  concurrency:
    group: ${{ github.workflow }}-${{ github.ref_name }}
    cancel-in-progress: true

  jobs:
    test:
      runs-on: ubuntu-latest
      env:
        MIX_ENV: test
      strategy:
        fail-fast: false
        matrix:
          include:
            - elixir: "#{@lint_elixir}"
              otp: "#{@lint_otp}"
              lint: lint
            - elixir: "1.18.4"
              otp: "27.2"
            - elixir: "1.17.3"
              otp: "27.2"
      steps:
        - uses: actions/checkout@v5

        - name: Install Elixir and Erlang
          uses: erlef/setup-beam@v1
          with:
            elixir-version: ${{ matrix.elixir }}
            otp-version: ${{ matrix.otp }}

        - name: Restore deps and _build cache
          uses: actions/cache@v5
          with:
            path: |
              deps
              _build
            key: ${{ runner.os }}-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('**/mix.lock') }}
            restore-keys: |
              ${{ runner.os }}-${{ matrix.elixir }}-${{ matrix.otp }}-

        - name: Install dependencies
          run: mix deps.get

        - name: Compile dependencies
          run: mix deps.compile

        - name: Check unused dependencies
          run: mix deps.unlock --check-unused
          if: ${{ matrix.lint }}

        - name: Check formatting
          run: mix format --check-formatted
          if: ${{ matrix.lint }}

        - name: Compile with warnings as errors
          run: mix compile --warnings-as-errors
          if: ${{ matrix.lint }}

        - name: Credo
          run: mix credo --strict
          if: ${{ matrix.lint }}

        - name: Restore PLT cache
          id: plt-cache
          uses: actions/cache@v5
          if: ${{ matrix.lint }}
          with:
            path: priv/plts
            key: plt-${{ runner.os }}-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('**/mix.lock') }}
            restore-keys: |
              plt-${{ runner.os }}-${{ matrix.elixir }}-${{ matrix.otp }}-

        - name: Create PLTs
          if: ${{ matrix.lint && steps.plt-cache.outputs.cache-hit != 'true' }}
          run: mix dialyzer --plt

        - name: Dialyzer
          run: mix dialyzer --format github
          if: ${{ matrix.lint }}

        - name: Run tests (lint row)
          run: mix test --cover
          if: ${{ matrix.lint }}

        - name: Run tests
          run: mix test
          if: ${{ !matrix.lint }}
  """

  # Publish workflow — fires on `v*` tag pushes for Hex packages. The setup
  # steps are inlined (no composite action) so the workflow is self-contained:
  # `mix ritual.install.ci` writes a setup-beam matrix for Hex packages and
  # does NOT install the mise composite action, so the publish workflow cannot
  # depend on one being present. The Elixir/OTP pair matches the lint row of
  # the setup-beam CI matrix above for consistency.
  #
  # `--replace` is intentionally omitted from `mix hex.publish` — the safe
  # default lets duplicate-version pushes fail loudly so authors bump the
  # version. Add `--replace` by hand only if you really mean to overwrite a
  # published tarball (which permanently changes the bytes that downstream
  # lockfiles point at).
  @publish ~s"""
  name: Publish to Hex

  on:
    push:
      tags:
        - "v*"

  env:
    MIX_ENV: prod

  jobs:
    publish:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v5

        - name: Install Elixir and Erlang
          uses: erlef/setup-beam@v1
          with:
            elixir-version: "#{@lint_elixir}"
            otp-version: "#{@lint_otp}"

        - name: Install dependencies
          run: mix deps.get

        - name: Build package
          run: mix hex.build

        - name: Publish to Hex
          run: mix hex.publish --yes
          env:
            HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
  """

  @doc "Returns the mise-style `ci.yml` body."
  @spec mise_ci() :: String.t()
  def mise_ci, do: @mise_ci

  @doc "Returns the mise composite setup action body."
  @spec mise_setup_action() :: String.t()
  def mise_setup_action, do: @mise_setup_action

  @doc "Returns the setup-beam matrix `ci.yml` body."
  @spec setup_beam_ci() :: String.t()
  def setup_beam_ci, do: @setup_beam_ci

  @doc "Returns the Hex publish workflow body."
  @spec publish_workflow() :: String.t()
  def publish_workflow, do: @publish
end
