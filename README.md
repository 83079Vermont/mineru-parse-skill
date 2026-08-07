# MinerU Parse Skill / MinerU 文档解析技能

> Local-first document parsing skill for AI coding agents (OpenCode / Claude Code / Cline / Codex / Cherry Studio / Gemini / Zcode), powered by [MinerU](https://github.com/opendatalab/MinerU).
>
> 面向 AI 编程代理的本地优先文档解析技能，基于 MinerU，支持多 Harness 适配。

## 中文

### 简介

`mineru-parse` 是一个供 Agent（OpenCode、Claude Code、Cline、Codex CLI、Cherry Studio、Gemini CLI、Zcode 等）使用的技能，用于把本地文档解析为 Markdown 后再读入上下文。它不依赖云服务，解析在本机完成（隐私安全），并由封装脚本统一处理缓存、批处理、清理与结果校验。

**适用格式**

| 类型 | 处理方式 |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | MinerU 解析为 Markdown |
| 单张 `jpg`/`jpeg`/`png`/`bmp` | 直接 Read（模型可看图，无需 OCR） |
| 批量图片 / 需要提取文字 | MinerU 解析 |
| 其他（txt、md、json、csv 等） | 默认方式读取 |

### 特性

- **单源多 Harness**：一份 `SKILL.md` 权威源，`generate-harnesses.ps1` 为 7 种 Harness 生成原生副本（frontmatter / 目录规范自动适配）
- **缓存**：产物比源文件新即复用，二次解析秒回；`-Force` 强制重解析
- **批处理**：多文件合并为一次 MinerU 调用，模型只加载一次
- **半自动部署**：首次使用 `deploy.ps1 -Scan` 扫描硬件（GPU/VRAM/内存/磁盘/Python）并推荐方案；`-Install` 交互安装，用户可自定义安装目录与模型目录
- **可配置定位**：通过环境变量 / `mineru.config.json` / 默认路径 / PATH 逐级探测 MinerU，不硬编码安装位置
- **结果校验**：空产物 `WARNING_EMPTY` 自动回退 Read；大文件分块读取提示
- **自动清理**：只保留 `.md`（`images/` 按策略），删除 JSON/PDF 等中间产物

### 快速开始

```powershell
# 1. 首次使用：检测 MinerU 是否已部署
& "<技能目录>\scripts\deploy.ps1" -Scan

# 2. 未部署则半自动安装（可指定安装/模型目录）
& "<技能目录>\scripts\deploy.ps1" -Install [-MinerUDir D:\MinerU] [-ModelDir D:\MinerU\models]

# 3. 解析文档
& "<技能目录>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"

# 4. 多文件批处理 + 强制重解析
& "<技能目录>\scripts\parse.ps1" -Paths a.pdf b.docx -Force

# 5. 导出到各 Agent Harness（user 级或 project 级）
& "<技能目录>\scripts\generate-harnesses.ps1" -Harness all -Scope user
```

### parse.ps1 参数

| 参数 | 说明 |
|---|---|
| `-Paths` | 输入文件绝对路径（可多个，批处理） |
| `-OutDir` | 输出目录。缺省：单文件→源目录；多文件→临时目录并复制回源目录 |
| `-Backend` | `auto`(默认)/`hybrid-engine`/`pipeline`/`vlm-engine` |
| `-Force` | 忽略缓存强制重解析 |
| `-KeepImages` | 保留 `images/` 目录 |
| `-NoFormula` | 关闭公式识别（默认开启） |
| `-Method` | `auto`(默认)/`txt`/`ocr` |
| `-Lang` | OCR 语言（默认 `ch`，仅 pipeline） |
| `-Effort` | `medium`(默认)/`high`（仅 hybrid） |

脚本输出 `RECOMMENDED_TIMEOUT_SECONDS=NNN`，执行超时应设置为该值以上。

### 目录结构

```
mineru-parse/
├── SKILL.md                    # 权威技能源（OpenCode 原生格式）
├── README.md                   # 本文档
├── scripts/
│   ├── parse.ps1               # 解析封装：缓存/批处理/清理/校验
│   ├── deploy.ps1              # 检测/硬件扫描/半自动安装
│   └── generate-harnesses.ps1  # 多 Harness 副本生成器
├── harnesses/
│   └── registry.json           # Harness 注册表（扩展点）
└── docs/
    ├── DEPLOYMENT.md           # 部署环境与故障排查
    └── HARNESSES.md            # 多 Harness 适配指南
```

### 文档

- [部署与故障排查](docs/DEPLOYMENT.md)
- [多 Harness 适配指南](docs/HARNESSES.md)

---

## English

### Overview

`mineru-parse` is a skill that lets AI coding agents (OpenCode, Claude Code, Cline, Codex CLI, Cherry Studio, Gemini CLI, Zcode, ...) turn local documents into Markdown before reading them into context. Parsing runs **locally** — no cloud service, privacy-safe — while wrapper scripts handle caching, batch parsing, cleanup, and result validation.

**Supported formats**

| Type | Handling |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | MinerU → Markdown |
| Single `jpg`/`jpeg`/`png`/`bmp` | Direct `Read` (model sees images, no OCR) |
| Image batches / text extraction needed | MinerU |
| Others (txt, md, json, csv, ...) | Default reading |

### Features

- **Single source, many harnesses**: one authoritative `SKILL.md`; `generate-harnesses.ps1` emits native copies for 7 harnesses (auto-adapted frontmatter & directory conventions)
- **Caching**: reuse `.md` newer than the source — instant on re-run; `-Force` to re-parse
- **Batching**: multiple files in a single MinerU invocation, models loaded once
- **Semi-automatic deployment**: `deploy.ps1 -Scan` probes hardware (GPU/VRAM/RAM/disk/Python) and recommends a plan; `-Install` installs interactively with user-chosen install & model directories
- **Configurable discovery**: `MINERU_BAT` env → `mineru.config.json` → default path → `PATH`; never hard-codes install location
- **Result validation**: `WARNING_EMPTY` on empty output falls back to `Read`; warns on very large files
- **Auto-cleanup**: keeps only `.md` (plus `images/` per policy), removes intermediate JSON/PDFs

### Quick Start

```powershell
# 1. First use: detect whether MinerU is installed
& "<skill-dir>\scripts\deploy.ps1" -Scan

# 2. If absent, semi-automatic install (custom dirs allowed)
& "<skill-dir>\scripts\deploy.ps1" -Install [-MinerUDir D:\MinerU] [-ModelDir D:\MinerU\models]

# 3. Parse a document
& "<skill-dir>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"

# 4. Batch parse + force re-parse
& "<skill-dir>\scripts\parse.ps1" -Paths a.pdf b.docx -Force

# 5. Export native copies to agent harnesses (user- or project-level)
& "<skill-dir>\scripts\generate-harnesses.ps1" -Harness all -Scope user
```

### parse.ps1 Parameters

| Parameter | Description |
|---|---|
| `-Paths` | Input files (multiple = batched) |
| `-OutDir` | Output root. Default: single file → source dir; multiple → temp dir then copied back |
| `-Backend` | `auto`(default)/`hybrid-engine`/`pipeline`/`vlm-engine` |
| `-Force` | Ignore cache, force re-parse |
| `-KeepImages` | Keep `images/` directory |
| `-NoFormula` | Disable formula recognition (enabled by default) |
| `-Method` | `auto`(default)/`txt`/`ocr` |
| `-Lang` | OCR language (default `ch`, pipeline only) |
| `-Effort` | `medium`(default)/`high` (hybrid only) |

The script prints `RECOMMENDED_TIMEOUT_SECONDS=NNN` — set your command timeout above that value.

### Directory Layout

```
mineru-parse/
├── SKILL.md                    # Authoritative skill source (OpenCode-native)
├── README.md                   # This document
├── scripts/
│   ├── parse.ps1               # Parse wrapper: cache/batch/cleanup/validate
│   ├── deploy.ps1              # Detect / hardware scan / semi-auto install
│   └── generate-harnesses.ps1  # Multi-harness copy generator
├── harnesses/
│   └── registry.json           # Harness registry (extension point)
└── docs/
    ├── DEPLOYMENT.md           # Deployment environment & troubleshooting
    └── HARNESSES.md            # Multi-harness adaptation guide
```

### Docs

- [Deployment & Troubleshooting](docs/DEPLOYMENT.md)
- [Multi-Harness Guide](docs/HARNESSES.md)

---

## License / 许可

MIT — 随附代码与脚本均可自由使用、修改与再分发。
