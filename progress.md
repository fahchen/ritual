# Progress — ritual

## 2026-05-07 会话 1

### 阶段 0 — 调研 + 写计划

**完成**

- 探查参考项目结构：muku（Phoenix + mise）、isaac_umbrella（umbrella + mise）、grephql（hex 包 + setup-beam）
- 读取所有相关配置文件：mix.exs、.formatter.exs、.credo.exs、.dialyzer_ignore.exs、CI workflows、composite actions、.tool-versions、mise.toml
- 取 Igniter 文档（context7：`/websites/hexdocs_pm_igniter`）：任务骨架、compose_task、add_dep、add_alias、create_new_file、copy_template、import_dep、TaskAliases
- 共性归纳完毕，差异点列入 `findings.md`
- 写计划：阶段 0–10、9 个子任务、形态检测、双风格 CI

### 创建/修改文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `task_plan.md` | new | 顶层计划，含子任务拓扑 |
| `findings.md` | new | Igniter API 笔记 + 跨项目共性矩阵 + 已知陷阱 |
| `progress.md` | new | 本文件 |

### 决策

- 用户增 isaac_umbrella + grephql 为参考。三项目共性显著（precommit、credo strict、dialyzer 配置）；差异主要在 CI 风格（mise vs setup-beam）与项目形态（umbrella、hex 包）
- 拆为 9 个独立子任务（format/credo/dialyzer/precommit/warnings_as_errors/tool_versions/ci/publish + 顶层 install）
- CI 双风格：`--style mise`（默认）、`--style setup-beam`
- `--matrix` flag 控制是否多版本矩阵
- 检测 umbrella/phoenix/hex_package 自动调整产物形态

### 下一步

进入阶段 1：项目骨架。先加 `:igniter` dep 至 mix.exs；建 `Ritual.Detect`、`Ritual.Templates` 命名空间；占位 `mix.tasks.ritual.install.ex`。等待用户确认计划再动手。

### 阶段 0 修订（codex review + 用户输入）

收 codex review；用户表态用 mise 管依赖。计划改：
- 子任务 9 → 8（删 `warnings_as_errors`）
- `tool_versions` → `toolchain`
- mise.toml 默认；`.tool-versions` 走 `--tool-versions` flag
- CI `--style` × `--matrix` flag 删；hex 包检测自动切 setup-beam
- format 永远开
- 阶段 2 单独去险 cli/0 注入
- 加 TDD 流程 + 每阶段 codex review loop + 小逻辑 commit

### 工作流定稿

```
每阶段：plan → red(test) → green(impl) → refactor → codex review → fix → commit
```

- 测试用 `Igniter.Test`
- 每子任务必含「跑两次幂等」用例
- conventional commits；单一逻辑单元；编译/格式/测试全绿才 commit
- codex review 直至无 issue

### 下一步

阶段 1：项目骨架 + igniter dep + 测试 helper。spawn 实现 subagent。

---

## 2026-05-07 会话 1（续）

### 阶段 1 — 项目骨架

**完成**

- spawn elixir subagent 实现 scaffold
- igniter `~> 0.7`（resolved 0.7.9）加入 deps
- `elixirc_paths/1` 设 test/support
- `Ritual.IgniterTestHelper` 建：`test_project/1` + `file_content/2`（注明触 `Rewrite` 内部）
- `.formatter.exs` 加 `import_deps: [:igniter]`
- 移除 `aliases test: ["test"]`（no-op）
- `igniter` 改 `runtime: false`（installer lib 标准）
- 移除空 smoke test
- `mix compile --warnings-as-errors`、`mix format --check-formatted`、`mix test` 全绿

### codex review

rescue agent 审（codex runtime 不可用）。actionable 五项，已全部应用：
1. `igniter` → `runtime: false`
2. 删 no-op `aliases`
3. 删 vacuous smoke test
4. `.formatter.exs` 加 `import_deps: [:igniter]`
5. `file_content/2` 加 `Rewrite` 内部 API 注释

### 关键发现：阶段 2 取消

`Igniter.Project.MixProject.update/4` 原生支持 `cli/0`、`aliases/0`、任意顶层函数（含自动创建）。findings #1 失效；阶段 2 cli/0 spike 不必再做。详见 findings.md「Igniter 测试 API」节。

阶段表更新：阶段 2 标 `skip`，跳至阶段 3（`Ritual.Detect`）。

### 创建/修改文件

| 文件 | 类型 |
|------|------|
| `mix.exs` | modified |
| `.formatter.exs` | modified |
| `lib/ritual.ex` | modified |
| `test/ritual_test.exs` | modified |
| `test/support/igniter_test_helper.ex` | new |
| `mix.lock` | new |

### 下一步

阶段 3：`Ritual.Detect` 模块（umbrella?/phoenix?/hex_package? 检测）。TDD：先写 detect 测试，再实现。后续阶段 4-11 各子任务依此构建。

---

## 2026-05-07 会话 1（续 2）

### 阶段 3 — Ritual.Detect

**完成**

- spawn elixir subagent TDD：red → green → refactor，14 测过
- 公共 API：`umbrella?/1`、`phoenix?/1`、`phoenix_live_view?/1`、`hex_package?/1`、`app_name/1`
- 实现：
  - `umbrella?` / `app_name` 走 `Igniter.Code.Function.move_to_def(:project, 0)` + `Common.rightmost/1` + `IKeyword.get_key/2`
  - `phoenix?` / `phoenix_live_view?` 用 `Igniter.Project.Deps.has_dep?/2`
  - `hex_package?` 检 `def package/0` 或 `defp package/0`
- 自实 `mix_zipper/1` 走 `Rewrite.source/2` + `Rewrite.Source.get(:quoted)`（已注 Igniter 内部 API）

### codex review

rescue agent 审（codex runtime 仍不可用）。三 actionable：
1. **Point 4**：`app_name/1` 改 `{:ok, atom} | :error`（无现有 caller，零迁移成本）— 已应用
2. **Point 1**：`do:` shorthand 限制 — **codex 误判**！实测 Igniter `move_to_def` 已正确处理 `do:` shorthand。改写为正向支持测试
3. **Point 6**：调用者若 igniter 已 queue mix.exs 写入，detect 读旧 AST — moduledoc 加警示

补测：phoenix+phoenix_live_view 共存、umbrella 含 :app、`def package(opts \\\\ [])` 假阳性、`def project, do:` shorthand 正确处理。

### 测试统计

18 tests, 0 failures。compile/format 全绿。

### 创建/修改文件

| 文件 | 类型 |
|------|------|
| `lib/ritual/detect.ex` | new |
| `test/ritual/detect_test.exs` | new |

### 下一步

阶段 4：`mix ritual.install.format`。TDD 实现 formatter 安装器，按 umbrella/phoenix/hex 形态分支。

---

## 2026-05-07 会话 1（续 3）

### 阶段 4 — mix ritual.install.format

**完成**

- spawn elixir subagent TDD：12 新测过
- `Mix.Tasks.Ritual.Install.Format` 薄壳 + `Ritual.Formatter` 共享模块
- 形态分支：plain / phoenix / umbrella / phoenix+umbrella；hex 包出 notice 不自动注 export
- 用 Igniter helpers：`Igniter.Project.Formatter.import_dep/2`、`add_formatter_plugin/2`、`Igniter.include_or_create_file/3`、`Igniter.update_elixir_file/3`
- 自实 `replace_default_keyword/4`、`ensure_keyword/3` 私 helper

### codex review（rescue agent）

11 项；其中 1 major、4 minor 已修，余为 nit：

| 项 | 严重 | 改 |
|----|------|---|
| `Zipper.replace(existing, value)` 缺 AST 规范化 | major | 改 `Common.replace_code/2` |
| 无条件 export 空骨架 = overreach | major | 删 `apply_hex_package/1`；改为 hex 包出 `Igniter.add_notice` |
| `@phoenix_import_deps` 顺序与 prepend 冲突 → 反字母序 | minor | 倒序为 `[:phoenix, :ecto_sql, :ecto]`，prepend 后字母序 |
| `apply_umbrella` 无条件覆 `inputs:` | minor | 改 `replace_default_keyword/4`：仅当现值等于默认 Mix-生成值才覆 |
| 缺测：malformed top、import_deps order、triple combo | minor | 三测皆补 |

### 测试统计

34 tests, 0 failures。

### 创建/修改文件

| 文件 | 类型 |
|------|------|
| `lib/mix/tasks/ritual/install/format.ex` | new |
| `lib/ritual/formatter.ex` | new |
| `test/mix/tasks/ritual/install/format_test.exs` | new |

### 下一步

阶段 5：`mix ritual.install.credo`。dep 注入 + `.credo.exs` 模板（default vs umbrella）+ EEx 渲染走 priv/templates。
