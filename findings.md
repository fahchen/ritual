# Findings — ritual 调研笔记

## Igniter 关键 API（来自 hexdocs.pm/igniter）

### 任务骨架
```elixir
defmodule Mix.Tasks.Ritual.Install.Credo do
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      group: :ritual,
      example: "mix ritual.install.credo",
      schema: [strict: :boolean],
      defaults: [strict: true],
      composes: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # ... mutations ...
    igniter
  end
end
```

### 常用变换
| 操作                  | API                                                          |
|----------------------|--------------------------------------------------------------|
| 加依赖                | `Igniter.Project.Deps.add_dep(igniter, {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false})` |
| 检测依赖              | `Igniter.Project.Deps.has_dep?(igniter, :phoenix)`            |
| 改 mix.exs `project/0` | `Igniter.Project.MixProject.update_project(igniter, key, fun)` |
| 加/改 alias           | `Igniter.Project.TaskAliases.add_alias(igniter, name, value, if_exists: :ignore)` |
| 加 import_deps formatter | `Igniter.Project.Formatter.import_dep(igniter, :phoenix)`   |
| 创建文件              | `Igniter.create_new_file(igniter, path, content, on_exists: :skip)` |
| 模板渲染              | `Igniter.copy_template(igniter, template_path, target, assigns)` |
| 应用名                | `Igniter.Project.Application.app_name(igniter)`               |
| 子任务编排            | `Igniter.compose_task(igniter, "ritual.install.credo", argv_or_nil)` |
| 增提示                | `Igniter.add_notice(igniter, msg)`                            |

### compose_task 注意
- 子任务默认仅看 `igniter.args.argv_flags`，不吃定位参数（防意外消费）
- `info/2` 必须在 `:composes` 列出所有被 compose 的子任务，否则未声明 flag 报错

## 跨参考项目共性矩阵

### precommit alias（三项目高度一致）
```elixir
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format",
  "credo --strict",
  "dialyzer",
  "test"
]
```
muku 中夹 JS 步（剔除）。isaac umbrella 多 `biome` 步（剔除）。

### cli/0
三项目皆有 `preferred_envs: [precommit: :test]`。

### dialyzer/0
```elixir
[
  plt_local_path: "priv/plts/<app>.plt",
  plt_core_path: "priv/plts/core.plt",
  plt_add_apps: [...],     # 至少 [:ex_unit, :mix]
  ignore_warnings: ".dialyzer_ignore.exs"  # 可选
]
```
muku 多 `[:phoenix_test, :phoenix_test_playwright]`；grephql 仅 `[:ex_unit, :mix]`。

### deps 三件套
```elixir
{:credo, "~> 1.6", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
```
isaac umbrella 顶层还加 `{:phoenix_live_view, ">= 0.0.0"}` 仅为 root `mix format` 处理 ~H 模板（umbrella+phoenix 时建议加）。

### .credo.exs（共同 enabled）
全部三项目共有的 strict checks（保留为默认模板）：
- Consistency.* 全部 8 项
- Design.AliasUsage、TagTODO、TagFIXME、DuplicatedCode（带 exclude_test_files）、SkipTestWithoutComment
- Readability.* 三十余项
- Refactor.* 全部 21 项（grephql/isaac 禁 ABCSize 与 ModuleDependencies；muku 启用 — 模板默认禁，留 flag）
- Warning.* 全部约 19 项

共同 disabled：
- AliasAs、BlockPipe、SingleFunctionToBlockPipe、VariableRebinding、LeakyEnvironment

差异点：
- `Specs`：muku 设 `files.excluded` + `include_defp: false`；isaac 用 `exclude_storybook_files`；grephql 用 `exclude_test_files` — 模板默认 `exclude_test_files`
- `MaxLineLength`：统一 `max_length: 120`
- `UnusedVariableNames`：muku/grephql 用 `force: :meaningful`；isaac 默认 — 模板默认 `force: :meaningful`
- `StrictModuleLayout`：muku 启用；isaac/grephql 禁 — 模板默认禁，留 flag
- `SeparateAliasRequire`：muku 启用；isaac/grephql 禁 — 模板默认禁
- `NestedFunctionCalls`：统一 `min_pipeline_length: 3`
- `Design.AliasUsage`：统一 `priority: :low, if_nested_deeper_than: 3, if_called_more_often_than: 1`

umbrella 模板增加项：
```elixir
files.included: ["lib/", "src/", "test/", "web/", "apps/*/lib/", "apps/*/src/", "apps/*/test/", "apps/*/web/"]
files.excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
```

### .formatter.exs（按形态）
- 普通库：`inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]`
- Hex 包：再加 `export: [locals_without_parens: ..., plugins: ...]`
- Phoenix 应用：加 `import_deps: [:ecto, :ecto_sql, :phoenix]` + `plugins: [Phoenix.LiveView.HTMLFormatter]`，可加 `subdirectories: ["priv/*/migrations"]`
- Umbrella：`inputs: ["mix.exs", "config/*.exs"]`、`subdirectories: ["apps/*"]`，可加 `plugins: [Phoenix.LiveView.HTMLFormatter]`

### .dialyzer_ignore.exs（默认）
默认建空骨架 + 注释示例（OTP 28 已知 MapSet 透明误报）：
```elixir
# Add false-positive Dialyzer warnings here.
# Each entry can be a regex, a {file, warning_type} tuple, or {file, warning_type, line}.
# Examples:
#   ~r/call_with(out)?_opaque.*opaque term/,
#   {"lib/foo.ex", :call_without_opaque}
[]
```

### CI workflows 双形态

#### muku/isaac 风（mise + 单 job + composite setup）
- `mise-action@v4`/`v3` 装 erlang/elixir
- composite `setup` action：mise → tool-versions out → hex/rebar → mix cache → deps.get/compile
- 单 job：deps.unlock --check-unused → format --check-formatted → compile --warnings-as-errors → credo --strict → PLT cache → dialyzer → test
- 需 `.tool-versions` 或 `mise.toml`

#### grephql 风（setup-beam + 矩阵 + lint flag）
- `erlef/setup-beam@v1` 矩阵多版本（含一行 `lint: lint`）
- lint 行跑全部 lint+test；其它行仅 test
- 不依赖 mise；适合 hex 包

### publish.yml（hex 发布，仅 grephql）
```yaml
on:
  push:
    tags: ["v*"]
jobs:
  publish:
    steps:
      - checkout
      - uses: ./.github/workflows/actions/setup
      - run: mix hex.build
      - run: mix hex.publish --yes --replace
        env:
          HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
```
仅在检测到 `package/0` 时启用。

### .tool-versions / mise.toml
- grephql 用 `.tool-versions`：`erlang 28.1\nelixir 1.19.5-otp-28`
- isaac 用 `mise.toml`（[tools] table 含 erlang/elixir + 项目附加工具）
- muku 用 mise

**决策（codex review 后翻默认）**：ritual 默认 `mise.toml`；`--tool-versions` flag 切 asdf 兼容格式。理由：用户与三参考项目中两项用 mise；mise.toml 表现力强（含 [tasks]、[env]、tasks alias 等扩展位）。

## 检测代码片段（用 Igniter）

```elixir
def umbrella?(igniter) do
  Igniter.Project.MixProject.read_project_config(igniter, :apps_path) != nil
end

def phoenix?(igniter), do: Igniter.Project.Deps.has_dep?(igniter, :phoenix)

def hex_package?(igniter) do
  # check for `package/0` definition in mix.exs
  ...
end
```
（API 名以实际 Igniter 为准；下一阶段验证。）

## 已知陷阱

1. ~~**`update_project/3` 不能改 `cli/0`**~~（**已失效，阶段 1 验证**）：`Igniter.Project.MixProject.update/4`（路径 `deps/igniter/lib/igniter/project/mix_project.ex:143`）原生支持任意顶层函数。其 docstring 直接给 `preferred_envs` 用例：
   ```elixir
   Igniter.Project.MixProject.update(igniter, :cli, [:preferred_envs, :"some.task"], fn _ -> {:ok, {:code, :test}} end)
   ```
   函数缺则自动建。`aliases/0`、`dialyzer/0` 同理。**阶段 2 不再需独立 spike**。
2. **`Igniter.Project.TaskAliases.add_alias` 默认 `:ignore`**：若已有 `precommit` alias 不会更新。需要 flag `--force` 时改 `:replace_or_append`。
3. **import_dep 顺序**：`Igniter.Project.Formatter.import_dep` 仅追加；不去重不排序 — 验证幂等性。
4. **OTP 28 dialyzer**：MapSet 透明类型误报很常见 — 模板注释要点出此事。
5. **YAML 模板**：`.github/workflows/ci.yml` 用 EEx 渲染时需注意 GitHub Actions 表达式 `${{ ... }}` 与 EEx `<%= %>` 共存：用 `<%%= %>` 转义或用 heredoc + 字符串拼接绕开。
6. **composite action 路径**：写到 `.github/workflows/actions/setup/action.yml` 还是 `.github/actions/setup/action.yml`？muku/grephql 都用 `.github/workflows/actions/setup/`（非标准但能跑） — 沿用此路径。
7. **`Rewrite` 是 Igniter 内部细节**：`igniter.rewrite` 字段不属公共 API；`Ritual.IgniterTestHelper.file_content/2` 单点访问，文档注明，将来 Igniter 改名只需改此处。
8. **`Igniter.Project.Deps.add_dep/3` 与 inline `defp deps, do: []` 形态不兼容**（阶段 5 实测）：当目标 mix.exs 用单行 `defp deps, do: []` 而非多行 `defp deps do [] end`，`add_dep` 会渲染出无效 Elixir。fixtures 一律用多行形 sidestep。**TODO：报上游 igniter issue**。
9. **`Igniter.create_new_file/4` `:skip` 在 test mode 不防覆**（阶段 5 实测）：`read_source!` 测试模式下读 `:test_files` assigns，但 `Map.put_new` 检 `igniter.rewrite.sources` — 测试 fixture 文件入 assigns 不入 sources，故 put_new 仍写。正解用 `Igniter.include_or_create_file/3`：read_source! 同走 test_files，但用 `Rewrite.put!` 入 sources，幂等正确。

## Igniter 测试 API（阶段 1 实测可用）

- `Igniter.Test.test_project/1` — 建内存测试项目；接 `:files`、`:app_name` 等
- `Igniter.Test.assert_has_patch/3` — 断言路径有 patch
- `Igniter.Test.assert_creates/2-3` — 断言新建文件（含内容比对）
- `Igniter.Test.assert_unchanged/1-2` — 断言无变更（幂等性测试用）
- `Igniter.Test.assert_has_notice/2` — 断言 `add_notice` 注信息

## 待确认（阶段 1-2 去险时验证）

- `Igniter.Project.MixProject.read_project_config/2` 真实存在与签名（下一阶段验证或换用 `update_project` 的 read 模式）
- 检测 `package/0` 是否要 `Igniter.Code.Module.move_to_def`
- Igniter 的 `copy_template/4` 对 EEx 模板中字面 `${{ ... }}` 是否安全
- **`cli/0` 注入路径**（阶段 2 spike）：是否需 `Igniter.Code.Module.find_and_update_module/3` + 自定义 zipper 操作；若太复杂可降级为生成新 `cli/0` 块或追加在文件末尾

## codex review 反馈（已采纳）

| 项 | 决定 |
|----|------|
| 删 `warnings_as_errors` 子任务 | 并入 `precommit` |
| 翻 mise 默认 | `mise.toml` 默认；`--tool-versions` 走 flag |
| 删 `--style` × `--matrix` 两 flag | hex 包检测自动切 setup-beam |
| `tool_versions` → `toolchain` | 名不绑格式 |
| format 永远开 | 顶层 install 必含；不可跳 |
| 阶段 5 cli/0 风险 | 提前为阶段 2 去险 spike |
| 简单 YAML 用字符串拼装 | 减 EEx-in-YAML `${{ }}` 转义面 |
