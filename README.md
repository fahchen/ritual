# Ritual

Composable [Igniter](https://hexdocs.pm/igniter)-based Mix tasks for
bootstrapping Elixir/Phoenix projects with consistent tooling.

One command, every project gets the same opinionated baseline:

- `.formatter.exs` shaped to the project (plain, Phoenix, umbrella)
- `mise.toml` (or `.tool-versions`) pinned to current Erlang/Elixir
- Credo strict config (`.credo.exs`) + the dep
- Dialyxir + `dialyzer:` keyword + `.dialyzer_ignore.exs`
- `precommit` mix alias and `cli/0` `preferred_envs`
- GitHub Actions CI workflow (mise single-job for apps; setup-beam matrix
  for Hex packages)
- Hex publish workflow (Hex packages only)

Every step preserves user customisations. Every step is idempotent.

## Install

Add to your `mix.exs` and run `mix deps.get`:

```elixir
def deps do
  [
    {:ritual, "~> 0.1", only: [:dev], runtime: false}
  ]
end
```

## Usage

Pick what to install interactively:

```bash
mix ritual.bootstrap        # prompts Install X? [Y/n] for each sub-task
mix ritual.bootstrap --yes  # skip prompts, compose every sub-task
```

Or run everything in one shot non-interactively (CI / automation):

```bash
mix ritual.install
```

Or run individual installers when you only want one piece:

```bash
mix ritual.install.format
mix ritual.install.toolchain                # mise.toml (default)
mix ritual.install.toolchain --tool-versions  # asdf-style .tool-versions
mix ritual.install.credo
mix ritual.install.dialyzer
mix ritual.install.precommit
mix ritual.install.ci
mix ritual.install.publish                  # Hex packages only
```

All installers detect project shape from `mix.exs` and adapt:

| Signal                               | Effect                                                            |
|--------------------------------------|-------------------------------------------------------------------|
| `apps_path:` in `project/0`          | Umbrella shape for `.formatter.exs` and `.credo.exs`              |
| `:phoenix` in deps                   | Phoenix `import_deps` + `Phoenix.LiveView.HTMLFormatter` plugin   |
| `package/0` in `mix.exs`             | `setup-beam` matrix CI; enables `mix ritual.install.publish`      |

## Order matters

`mix ritual.install` runs sub-tasks in this order:

1. `format`
2. `toolchain`
3. `credo`     — adds `:credo` dep
4. `dialyzer`  — adds `:dialyxir` dep
5. `precommit` — reads `:credo` / `:dialyxir` from the in-memory mix.exs
6. `ci`
7. `publish`

Steps 3-4 must precede step 5 so `precommit` can include `mix credo --strict`
and `mix dialyzer` in the alias when those tools are present.

## Idempotency

Re-running any installer is a no-op:

- Existing config files (`.formatter.exs`, `.credo.exs`, `.dialyzer_ignore.exs`,
  `mise.toml`, `.tool-versions`, `.github/workflows/*.yml`) are **never**
  overwritten.
- Existing `dialyzer:` block in `mix.exs` is left verbatim.
- Existing `precommit:` alias is preserved; a notice spells out the canonical
  shape so users can compare and merge by hand.
- Existing dep declarations (`:credo`, `:dialyxir`) keep their version
  pin and opts.

## What it does NOT do

- No JS/frontend tooling (no pnpm, no playwright, no esbuild, no tailwind).
  See `task_plan.md` for the rationale.
- No `--style` / `--matrix` flags on the CI installer in v0 — auto-selection
  on `package/0` covers the two common cases.
- No automatic `export:` block in `.formatter.exs` for Hex packages — empty
  `locals_without_parens: []` is meaningless noise. The format task emits a
  notice instead so authors can fill it in deliberately.

## Reference

The opinionated defaults are distilled from three real Elixir projects:
muku (Phoenix LiveView application + mise CI), isaac_umbrella
(umbrella + mise), grephql (Hex library + setup-beam matrix CI). The common
subset of strict Credo checks, the precommit alias steps, the dialyzer
config shape, and the CI workflow choices all come from comparing those.

## License

MIT.
