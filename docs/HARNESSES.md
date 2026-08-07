# 多 Harness 适配指南

本技能以单一 `SKILL.md` 为权威源，通过 `scripts/generate-harnesses.ps1` 为各 Agent Harness 生成原生副本。生成的副本包含 `SKILL.md`（带该 harness 规范的 frontmatter）、`scripts\` 与 `docs\`（保持相对结构，`SKILL.md` 内用相对路径引用）。

## 生成用法

```powershell
# 全部 harness，用户级（会逐个询问 user/project）
& scripts\generate-harnesses.ps1 -Harness all

# 指定某些，项目级
& scripts\generate-harnesses.ps1 -Harness opencode,claude,cline -Scope project

# 显式输出目录（调试，不写入真实配置目录）
& scripts\generate-harnesses.ps1 -Harness claude -TargetDir D:\tmp\test

# 覆盖已有副本
& scripts\generate-harnesses.ps1 -Harness all -Force
```

## Harness 能力矩阵

| Harness | 状态 | 用户级目录 | 项目级目录 | 特殊要求 |
|---|---|---|---|---|
| OpenCode | native | `~/.config/opencode/skills/mineru-parse` | `.opencode/skills/mineru-parse` | YAML frontmatter（name/description） |
| Claude Code | native | `~/.claude/skills/mineru-parse` | `.claude/skills/mineru-parse` | 已加 `allowed-tools: Bash(*)`，可按需收紧 |
| Cline | native | `~/.cline/skills/mineru-parse` | `.cline/skills/mineru-parse` | name 须与目录同名（kebab-case）；description ≤ 1024 字符 |
| Codex CLI | native | `~/.codex/skills/mineru-parse` | `.codex/skills/mineru-parse` | 正文 ≤ 8KB（生成时自动检查） |
| Cherry Studio | compatible | 复用 Claude 目录 | 复用 Claude 目录 | 兼容 `.claude/skills/` 格式 |
| Gemini CLI | native | `~/.gemini/skills/mineru-parse` | `.gemini/skills/mineru-parse` | 原生 TOML 格式（当前简化版） |
| Zcode | extension-point | `~/.zcode/skills/mineru-parse` | `.zcode/skills/mineru-parse` | 规范待确认，暂生成通用占位 |

## 生成逻辑

1. 读取 `harnesses/registry.json`（各 harness 的目录、frontmatter、格式、状态）
2. 从权威 `SKILL.md` 提取正文（去除其自带 frontmatter）
3. 按 registry 中的 frontmatter 生成目标 `SKILL.md`；`status=compatible` 复用 `reuse` 指向的 harness 配置
4. 复制 `scripts\` 与 `docs\`（保持相对结构，脚本通过相对路径解析）
5. `status=extension-point` 仅生成占位目录并提示

## 新增一个 Harness

在 `harnesses/registry.json` 的 `harnesses` 下新增条目即可，生成脚本自动适配：

```json
"myharness": {
  "status": "native",
  "userDir": "~/.myharness/skills/mineru-parse",
  "projectDir": ".myharness/skills/mineru-parse",
  "frontmatter": {
    "name": "mineru-parse",
    "description": "<该 harness 的触发描述>"
  },
  "notes": "<注意事项>"
}
```

若新 harness 完全复用另一 harness 的格式（如 Cherry Studio 复用 Claude）：

```json
"other": {
  "status": "compatible",
  "reuse": "claude",
  "notes": "兼容描述"
}
```

修改后运行 `generate-harnesses.ps1 -Harness myharness -TargetDir <调试目录>` 验证输出。

## 注意事项

- **跨平台 OS**：当前脚本为 Windows / PowerShell。macOS / Linux 的等价 `parse.sh` 可后续以同样扩展点方式加入 registry
- **SKILL.md 体积**：Codex 有 8KB 上限；若未来正文增长超出，可将详细说明移入 `docs/` 并在正文用相对路径引用（各 harness 均支持）
- **脚本可移植性**：`parse.ps1` / `deploy.ps1` 通过 `mineru.config.json` 定位 MinerU（`deploy.ps1 -Install` 自动生成），不依赖绝对路径
