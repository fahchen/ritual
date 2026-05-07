# 任务计划：ritual — Elixir 工具链 Igniter 安装器

## 目标

以 [Igniter](https://hexdocs.pm/igniter) 为基，构建 `ritual` 库。该库提供一组组合式 Mix 任务，向任意 Elixir/Phoenix（含 umbrella、Hex 包）项目一键注入或更新工具链：依赖、配置文件、mix.exs 配置、aliases、GitHub Actions workflows。

参考样板（仅 Elixir/Phoenix 部分，**忽略 JS/前端**）：
- `/Users/fahchen/PersonalProjects/muku` — Phoenix LV 全栈应用（mise + 单 job CI）
- `/Users/fahchen/PersonalProjects/isaac_umbrella` — umbrella 应用（mise）
- `/Users/fahchen/PersonalProjects/grephql` — Hex 库（setup-beam 矩阵 CI + publish workflow）

## 子命令拓扑（v0，8 条）

每条命令独立可调用，亦可被 `mix ritual.install` 聚合。

| 命令                              | 职责                                                                                |
|-----------------------------------|------------------------------------------------------------------------------------|
| `mix ritual.install`              | 顶层聚合：format → toolchain → credo → dialyzer → precommit → ci → publish（如适用）|
| `mix ritual.install.format`       | 写/扩 `.formatter.exs`；按 umbrella/phoenix/hex 形态调整；**始终在顶层 install 中开启** |
| `mix ritual.install.credo`        | 加 credo dep + 写 `.credo.exs`；default vs umbrella 模板                             |
| `mix ritual.install.dialyzer`     | 加 dialyxir dep + mix.exs `dialyzer/0` + 空 `.dialyzer_ignore.exs`                   |
| `mix ritual.install.precommit`    | 注 `aliases :precommit`（含 `compile --warnings-as-errors`）+ `cli/0` `preferred_envs` |
| `mix ritual.install.toolchain`    | 写 `mise.toml`（默认）；`--tool-versions` 切 `.tool-versions`（asdf 兼容）            |
| `mix ritual.install.ci`           | `.github/workflows/ci.yml` + composite setup action；hex 包自动切 setup-beam 矩阵风格 |
| `mix ritual.install.publish`      | `.github/workflows/publish.yml`（仅检测到 `package/0`）                              |

**v0 删除项**（codex review 后定）：
- ~~`warnings_as_errors` 独立命令~~ — 太薄，并入 `precommit`
- ~~CI `--style mise\|setup-beam` flag~~ — 默认 mise；hex 包检测自动切 setup-beam
- ~~CI `--matrix` flag~~ — 冗余于 setup-beam 风
- ~~`tool_versions` 命名~~ — 改 `toolchain`（不绑死格式）

## 检测策略

各任务在 `igniter/1` 内读 mix.exs AST 决定输出形态：

| 形态     | 信号                                  | 影响                                              |
|----------|---------------------------------------|--------------------------------------------------|
| umbrella | `project/0` 含 `apps_path:`           | formatter `subdirectories: ["apps/*"]`、credo `included` 加 `apps/*/`|
| Phoenix  | deps 含 `:phoenix`                    | formatter `import_deps: [:phoenix, :ecto, ...]`、`Phoenix.LiveView.HTMLFormatter` |
| Hex 包   | `project/0` 有 `package/0`            | formatter 加 `export:`；启用 `publish` 任务；CI 自动切 setup-beam 矩阵 |

集中于 `Ritual.Detect` 模块。

## 架构骨架

```
ritual/
├── mix.exs                              # +igniter dep
├── lib/
│   ├── ritual.ex
│   ├── ritual/
│   │   ├── detect.ex                    # umbrella?/phoenix?/hex_package?
│   │   ├── templates.ex                 # priv/templates 路径辅助
│   │   └── mix_project.ex               # mix.exs 改写工具（含 cli/0 注入）
│   └── mix/tasks/
│       ├── ritual.install.ex
│       └── ritual/install/
│           ├── format.ex
│           ├── credo.ex
│           ├── dialyzer.ex
│           ├── precommit.ex
│           ├── toolchain.ex
│           ├── ci.ex
│           └── publish.ex
├── priv/templates/
│   ├── credo/
│   │   ├── default.credo.exs.eex
│   │   └── umbrella.credo.exs.eex
│   ├── dialyzer/
│   │   └── ignore.exs.eex
│   ├── ci/
│   │   ├── mise/
│   │   │   ├── ci.yml.eex
│   │   │   └── setup_action.yml.eex
│   │   └── setup_beam/
│   │       └── ci.yml.eex
│   ├── publish/
│   │   └── publish.yml.eex
│   └── toolchain/
│       ├── mise.toml.eex
│       └── tool-versions.eex
└── test/
    ├── support/igniter_helper.ex
    └── mix/tasks/...
```

## 工作流：TDD + 小 commit + codex review loop

每阶段闭环：

```
plan → red(test) → green(impl) → refactor → codex review → fix → commit
```

- **红**：先写 `test/mix/tasks/<task>_test.exs`，用 `Igniter.Test` 助手 assert 文件内容/diff/依赖
- **绿**：最小实现使测试通过
- **重构**：清理重复，跨任务抽 `Ritual.Detect`、`Ritual.MixProject`
- **codex review**：每阶段完成 staged 改动后 spawn codex（rescue agent）审：API 用法、边界、idempotent
- **修**：依 codex 反馈调整；再 review 直至无问题
- **commit**：单一逻辑单元；conventional commits（`feat:`、`test:`、`refactor:`、`docs:`）

### Commit 粒度规范

| 粒度 | 准 |
|------|---|
| 一个 commit | 一个完整可验证单元（一条子任务的红+绿+测试通过；或一处重构；或一段文档） |
| 不可 | 跨子任务 commit；半成品 commit；test 与 impl 拆 commit（test 应在同 commit 含 fixture） |
| 必须 | `mix compile`、`mix format`、`mix test` 全绿才提交 |

## 阶段

| #  | 阶段                                             | 状态     | TDD？ | Commit |
|----|-------------------------------------------------|---------|-------|--------|
| 0  | 调研 + 写计划                                    | complete | n/a   | `docs: add ritual planning files` |
| 1  | 项目骨架 + igniter dep + 测试 helper             | complete | 部分  | `chore: scaffold ritual with igniter dep` |
| 2  | ~~`cli/0` 注入 spike~~（**取消**：`MixProject.update/4` 原生支持，见 findings #1）| skip | n/a | — |
| 3  | `Ritual.Detect`：umbrella/phoenix/hex 检测       | complete | yes   | `feat: add project shape detection` |
| 4  | `mix ritual.install.format`                      | complete | yes   | `feat: add format installer` |
| 5  | `mix ritual.install.credo`                       | complete | yes   | `feat: add credo installer` |
| 6  | `mix ritual.install.dialyzer`                    | complete | yes   | `feat: add dialyzer installer` |
| 7  | `mix ritual.install.precommit`                   | complete | yes   | `feat: add precommit installer` |
| 8  | `mix ritual.install.toolchain`（mise 默认）      | complete | yes   | `feat: add toolchain installer (mise default)` |
| 9  | `mix ritual.install.ci`（mise + setup-beam 自动选）| pending | yes   | `feat: add ci installer` |
| 10 | `mix ritual.install.publish`                     | pending  | yes   | `feat: add publish installer` |
| 11 | `mix ritual.install` 顶层聚合                    | pending  | yes   | `feat: add top-level install task` |
| 12 | README + moduledoc                               | pending  | n/a   | `docs: add README and module docs` |

阶段 1-2 提前以**去险**：cli/0 注入是 Igniter 已知陷阱（findings #1）；先确认 API 路径，再展开后续阶段。

## 决策（codex review 后定稿）

- **JS 全剔**：所有参考项目的 pnpm/playwright/tailwind/esbuild/bun/biome 一律不抄
- **mise 默认**：`mise.toml` 默认；`--tool-versions` flag 切 asdf 格式
- **format 永远开**：顶层 `install` 必含；不提供 skip flag
- **CI 风格自动**：默认 mise 单 job；`hex_package?` 自动改用 setup-beam 矩阵风（grephql 风）
- **precommit 含 warnings**：`compile --warnings-as-errors` 是 `precommit` alias 的第一步；不再独立子任务
- **去险优先**：cli/0 注入在阶段 2 单独验证，再上层
- **idempotent**：所有任务可重复跑；每个子任务测试至少含一条「跑两次幂等」用例
- **YAML 模板**：用 EEx + `<%%= %>` 转义 GitHub Actions `${{ }}`；或简单 workflow 用纯字符串拼装
- **wenyan/caveman**：计划/进度用文白；代码、commit、PR 走标准英文

## 三次失败协议

诸器若三试不成，止手向用户求助；勿盲撞同径。

## 遇到的错误

| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| —    | —       | —       |

## 参考

详见 `findings.md`。
