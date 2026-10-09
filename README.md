# MinerU Parse Skill / MinerU 文档解析技能

[![MinerU](https://img.shields.io/badge/MinerU-4.0-blue)](https://github.com/opendatalab/MinerU)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Harnesses](https://img.shields.io/badge/harnesses-8-informational)](harnesses/registry.json)

> Local-first document parsing skill for AI coding agents (OpenCode / Claude Code / Cline / Codex / Cherry Studio / Gemini / Zcode / DSH), powered by [MinerU](https://github.com/opendatalab/MinerU) **4.0**.
>
> 面向 AI 编程代理的本地优先文档解析技能，基于 MinerU **4.0**，支持多 Harness 适配。

## 中文

### 简介

`mineru-parse` 是一个供 Agent（OpenCode、Claude Code、Cline、Codex CLI、Cherry Studio、Gemini CLI、Zcode、DSH 等）使用的技能，用于把本地文档解析为 Markdown 后再读入上下文。它不依赖云服务，解析在本机完成（隐私安全），并由封装脚本统一处理缓存、批处理与结果校验。

**适用格式**

| 类型 | 处理方式 |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | MinerU 解析为 Markdown |
| 单张 `jpg`/`jpeg`/`png`/`bmp` | 直接 Read（模型可看图，无需 OCR） |
| 批量图片 / 需要提取文字 | MinerU 解析 |
| 其他（txt、md、json、csv 等） | 默认方式读取 |

### 特性

- **MinerU 4.0 档位模型**：`flash`/`basic`/`standard`/`advanced` 四档质量，取代 3.x 的 backend；`auto` 规则 = 非 PDF→flash、PDF<10 页→basic、否则 standard
- **单源多 Harness**：一份 `SKILL.md` 权威源，`generate-harnesses.ps1` 为 8 种 Harness 生成原生副本（frontmatter / 目录规范自动适配）
- **缓存**：产物比源文件新即复用，二次解析秒回；`-Force` 强制重解析
- **批处理**：多文件合并为一次 MinerU 调用，模型只加载一次
- **自包含产物**：markdown 输出把图片内联为 base64，不产生 `images/` 等中间文件；需要图片文件时用 `-Format zip`
- **向后兼容**：3.x 的 `-Backend`/`-Method`/`-Effort`/`-NoFormula` 仍被接受并自动映射（打印 `WARN_DEPRECATED`）
- **沙箱适配**：`scripts/sandbox/sitecustomize.py` 修复 DSH Windows 沙箱下的临时目录权限问题，`parse.ps1` 自动注入
- **半自动部署**：`deploy.ps1 -Scan`（Windows）/ `deploy.sh --scan`（WSL/Linux）扫描硬件（GPU/VRAM/内存/磁盘/Python）并推荐方案；`-Install` / `--install --yes` 交互或非交互安装
- **可配置定位**：Windows 经 `MINERU_KIT_BAT` / `mineru.config.json`；WSL/Linux 经 `MINERU_KIT_BIN` / `mineru.config.linux.json`；两份配置独立，双系统并存互不干扰
- **结果校验**：空产物 `WARNING_EMPTY` 自动回退 Read；大文件分块读取提示

### 支持的 Harness

由 `generate-harnesses.ps1` 从 `harnesses/registry.json` 生成原生副本：

| Harness | 适配状态 | 用户级目录 |
|---|---|---|
| OpenCode | 原生 | `~/.config/opencode/skills/mineru-parse` |
| Claude Code | 原生 | `~/.claude/skills/mineru-parse` |
| Cline | 原生 | `~/.cline/skills/mineru-parse` |
| Codex | 原生 | `~/.codex/skills/mineru-parse` |
| Gemini | 原生 | `~/.gemini/skills/mineru-parse` |
| DSH | 原生 | `~/.dsh/skills/mineru-parse` |
| Cherry Studio | 兼容（复用 Claude 格式） | `~/.claude/skills/mineru-parse` |
| Zcode | 扩展点 | `~/.zcode/skills/mineru-parse` |

### 快速开始

Windows（PowerShell）：

```powershell
# 1. 首次使用：检测 MinerU 是否已部署
& "<技能目录>\scripts\deploy.ps1" -Scan

# 2. 未部署则半自动安装（可指定安装/模型目录）
& "<技能目录>\scripts\deploy.ps1" -Install [-MinerUDir D:\MinerU] [-ModelDir D:\MinerU\models]

# 3. 解析文档
& "<技能目录>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"

# 4. 多文件批处理 + 强制重解析 + 指定档位（PowerShell 中多文件用逗号分隔）
& "<技能目录>\scripts\parse.ps1" -Paths a.pdf,b.docx -Tier standard -Force

# 5. 导出到各 Agent Harness（user 级或 project 级）
& "<技能目录>\scripts\generate-harnesses.ps1" -Harness all -Scope user
```

WSL / Linux（bash）：

```bash
# 1. 检测
"<技能目录>/scripts/deploy.sh" --scan

# 2. 非交互安装（uv + mineru[torch]==4.0.10 + CUDA torch + llama.cpp VLM）
"<技能目录>/scripts/deploy.sh" --install --yes

# 3. 解析文档（Windows 路径先转 /mnt/d/...）
"<技能目录>/scripts/parse.sh" -Paths "/mnt/d/docs/paper.pdf"

# 4. 多文件批处理 + 强制重解析
"<技能目录>/scripts/parse.sh" -Paths a.pdf b.docx -Force
```

### parse 脚本参数（.ps1 / .sh 同义）

| 参数 | 说明 |
|---|---|
| `-Paths` | 输入文件绝对路径（可多个；**PowerShell 用逗号分隔** `-Paths a.pdf,b.docx`，bash 用空格分隔） |
| `-OutDir` | 输出目录。缺省：单文件→源目录；多文件→临时目录并复制回源目录 |
| `-Tier` | `auto`(默认)/`flash`/`basic`/`standard`/`advanced` |
| `-Pages` | PDF 页范围，如 `1-5,8` / `r3-r1` / `all` |
| `-Format` | `markdown`(默认)/`middle_json`/`zip` |
| `-OcrMode` | `auto`(默认)/`txt`/`ocr` |
| `-NoImageAnalysis` | 关闭图像分析 |
| `-Force` | 忽略缓存强制重解析 |
| `-KeepImages` | 已废弃（markdown 内联图片；要图片文件请用 `-Format zip`） |

3.x 旧参数 `-Backend` / `-Method` / `-Lang` / `-Effort` / `-NoFormula` 仍被接受，自动映射或告警忽略。

脚本输出 `RECOMMENDED_TIMEOUT_SECONDS=NNN`，执行超时应设置为该值以上。

### 目录结构

```
mineru-parse/
├── SKILL.md                    # 权威技能源（OpenCode 原生格式）
├── README.md                   # 本文档
├── LICENSE                     # MIT 许可
├── mineru.config.example.json  # Windows 定位配置模板（复制为 mineru.config.json 后填本机路径）
├── scripts/
│   ├── parse.ps1               # 解析封装（Windows）：缓存/批处理/校验
│   ├── parse.sh                # 解析封装（Linux/WSL）：与 .ps1 同义
│   ├── deploy.ps1              # 检测/硬件扫描/半自动安装（Windows，MinerU 4.0）
│   ├── deploy.sh               # 检测/硬件扫描/uv 原生安装（Linux/WSL，MinerU 4.0）
│   ├── generate-harnesses.ps1  # 多 Harness 副本生成器
│   ├── mineru.config.linux.example.json  # WSL/Linux 定位配置模板
│   └── sandbox/
│       └── sitecustomize.py    # DSH 沙箱临时目录权限修复（parse.ps1 自动注入）
├── harnesses/
│   └── registry.json           # Harness 注册表（扩展点）
└── docs/
    ├── DEPLOYMENT.md           # 部署环境、迁移与故障排查
    └── HARNESSES.md            # 多 Harness 适配指南
```

### 从仓库安装

本仓库**根目录即技能根目录**（`SKILL.md` 位于仓库顶层），clone 到位即可被 Harness 识别：

```bash
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.dsh/skills/mineru-parse               # DSH（用户级）
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.config/opencode/skills/mineru-parse   # OpenCode（用户级）
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.claude/skills/mineru-parse            # Claude Code / Cherry Studio
```

Windows 下把 `~` 换成 `%USERPROFILE%`（如 `%USERPROFILE%\.dsh\skills\mineru-parse`）。

仓库里的 `mineru.config.example.json` 与 `scripts/mineru.config.linux.example.json` **只是模板**：
首次使用请先跑 `scripts/deploy.ps1 -Scan`（Windows）/ `scripts/deploy.sh --scan`（WSL/Linux），
或手工复制成 `mineru.config.json` / `scripts/mineru.config.linux.json` 并填入本机 MinerU 路径。
这两份本机生成的配置已列入 `.gitignore`，不会被提交。

### 文档

- [部署与故障排查](docs/DEPLOYMENT.md)
- [多 Harness 适配指南](docs/HARNESSES.md)

---

## English

### Overview

`mineru-parse` is a skill that lets AI coding agents (OpenCode, Claude Code, Cline, Codex CLI, Cherry Studio, Gemini CLI, Zcode, DSH, ...) turn local documents into Markdown before reading them into context. Parsing runs **locally** — no cloud service, privacy-safe — while wrapper scripts handle caching, batch parsing, and result validation.

**Supported formats**

| Type | Handling |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | MinerU → Markdown |
| Single `jpg`/`jpeg`/`png`/`bmp` | Direct `Read` (model sees images, no OCR) |
| Image batches / text extraction needed | MinerU |
| Others (txt, md, json, csv, ...) | Default reading |

### Features

- **MinerU 4.0 tiers**: `flash`/`basic`/`standard`/`advanced` replace the 3.x backends; `auto` = non-PDF→flash, PDF <10 pages→basic, else standard
- **Single source, many harnesses**: one authoritative `SKILL.md`; `generate-harnesses.ps1` emits native copies for 8 harnesses
- **Caching**: reuse `.md` newer than the source — instant on re-run; `-Force` to re-parse
- **Batching**: multiple files in a single MinerU invocation, models loaded once
- **Self-contained output**: markdown inlines images as base64 — no `images/` side files; use `-Format zip` when you need image files
- **Backward compatible**: 3.x `-Backend`/`-Method`/`-Effort`/`-NoFormula` are still accepted and auto-mapped (with a `WARN_DEPRECATED` line)
- **Sandbox aware**: `scripts/sandbox/sitecustomize.py` fixes the DSH Windows sandbox temp-dir permission problem; `parse.ps1` injects it automatically
- **Semi-automatic deployment**: `deploy.ps1 -Scan` / `deploy.sh --scan` probe hardware and recommend a plan; `-Install` / `--install --yes` install interactively or non-interactively
- **Configurable discovery**: Windows via `MINERU_KIT_BAT` / `mineru.config.json`; WSL/Linux via `MINERU_KIT_BIN` / `mineru.config.linux.json`
- **Result validation**: `WARNING_EMPTY` on empty output falls back to `Read`

### Supported Harnesses

`generate-harnesses.ps1` emits native copies from `harnesses/registry.json`:

| Harness | Status | User directory |
|---|---|---|
| OpenCode | native | `~/.config/opencode/skills/mineru-parse` |
| Claude Code | native | `~/.claude/skills/mineru-parse` |
| Cline | native | `~/.cline/skills/mineru-parse` |
| Codex | native | `~/.codex/skills/mineru-parse` |
| Gemini | native | `~/.gemini/skills/mineru-parse` |
| DSH | native | `~/.dsh/skills/mineru-parse` |
| Cherry Studio | compatible (reuses the Claude format) | `~/.claude/skills/mineru-parse` |
| Zcode | extension point | `~/.zcode/skills/mineru-parse` |

### Quick Start

Windows (PowerShell):

```powershell
& "<skill-dir>\scripts\deploy.ps1" -Scan
& "<skill-dir>\scripts\deploy.ps1" -Install [-MinerUDir D:\MinerU] [-ModelDir D:\MinerU\models]
& "<skill-dir>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"
& "<skill-dir>\scripts\parse.ps1" -Paths a.pdf,b.docx -Tier standard -Force
& "<skill-dir>\scripts\generate-harnesses.ps1" -Harness all -Scope user
```

WSL / Linux (bash):

```bash
"<skill-dir>/scripts/deploy.sh" --scan
"<skill-dir>/scripts/deploy.sh" --install --yes
"<skill-dir>/scripts/parse.sh" -Paths "/mnt/d/docs/paper.pdf"
"<skill-dir>/scripts/parse.sh" -Paths a.pdf b.docx -Force
```

### parse script parameters (same for .ps1 / .sh)

| Parameter | Description |
|---|---|
| `-Paths` | Input files (multiple = batched; **PowerShell needs commas** `-Paths a.pdf,b.docx`, bash uses spaces) |
| `-OutDir` | Output root. Default: single file → source dir; multiple → temp dir then copied back |
| `-Tier` | `auto`(default)/`flash`/`basic`/`standard`/`advanced` |
| `-Pages` | PDF page range, e.g. `1-5,8` / `r3-r1` / `all` |
| `-Format` | `markdown`(default)/`middle_json`/`zip` |
| `-OcrMode` | `auto`(default)/`txt`/`ocr` |
| `-NoImageAnalysis` | Disable image analysis |
| `-Force` | Ignore cache, force re-parse |
| `-KeepImages` | Deprecated (markdown inlines images; use `-Format zip` for image files) |

Legacy 3.x parameters (`-Backend` / `-Method` / `-Lang` / `-Effort` / `-NoFormula`) are accepted and mapped or ignored with a warning.

The script prints `RECOMMENDED_TIMEOUT_SECONDS=NNN` — set your command timeout above that value.

### Directory Layout

```
mineru-parse/
├── SKILL.md                    # Authoritative skill source (OpenCode-native)
├── README.md                   # This document
├── LICENSE                     # MIT license
├── mineru.config.example.json  # Windows discovery config template (copy to mineru.config.json)
├── scripts/
│   ├── parse.ps1               # Parse wrapper (Windows)
│   ├── parse.sh                # Parse wrapper (Linux/WSL)
│   ├── deploy.ps1              # Detect / hardware scan / install (Windows, MinerU 4.0)
│   ├── deploy.sh               # Detect / hardware scan / uv install (Linux/WSL, MinerU 4.0)
│   ├── generate-harnesses.ps1  # Multi-harness copy generator
│   ├── mineru.config.linux.example.json  # WSL/Linux discovery config template
│   └── sandbox/
│       └── sitecustomize.py    # DSH sandbox temp-dir fix (auto-injected)
├── harnesses/
│   └── registry.json           # Harness registry (extension point)
└── docs/
    ├── DEPLOYMENT.md           # Deployment, migration & troubleshooting
    └── HARNESSES.md            # Multi-harness adaptation guide
```

### Install from the repository

The repository root **is** the skill root (`SKILL.md` at the top), so a clone is all you need:

```bash
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.dsh/skills/mineru-parse               # DSH (user scope)
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.config/opencode/skills/mineru-parse   # OpenCode (user scope)
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.claude/skills/mineru-parse            # Claude Code / Cherry Studio
```

On Windows replace `~` with `%USERPROFILE%` (e.g. `%USERPROFILE%\.dsh\skills\mineru-parse`).

`mineru.config.example.json` and `scripts/mineru.config.linux.example.json` are **templates only**.
On first use run `scripts/deploy.ps1 -Scan` (Windows) / `scripts/deploy.sh --scan` (WSL/Linux), or copy
a template to `mineru.config.json` / `scripts/mineru.config.linux.json` and fill in your local MinerU
paths. Your machine-generated copies are gitignored.

### Docs

- [Deployment & Troubleshooting](docs/DEPLOYMENT.md)
- [Multi-Harness Guide](docs/HARNESSES.md)

---

## License / 许可

[MIT](LICENSE) — 随附代码与脚本均可自由使用、修改与再分发。
