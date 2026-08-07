---
name: mineru-parse
description: 使用本地 MinerU 解析文档。当用户输入或附带 PDF、DOCX、PPTX、XLSX、TIFF/TIF 或批量图片（jpg/jpeg/png/bmp/tif/tiff）文件时，默认调用 MinerU 将其解析为 Markdown 再读取；单张 jpg/jpeg/png/bmp 图片直接用 Read 工具读取；其他格式使用 Opencode 默认解析。触发词：mineru、pdf、docx、pptx、xlsx、tiff、解析、parse、parse_docs。
---

# MinerU 文档解析

当用户向 Opencode 输入文件时，按扩展名（不区分大小写）选择解析方式：

## 格式判定

| 类型 | 处理方式 |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | 走 MinerU 解析流程 |
| 单张 `jpg`/`jpeg`/`png`/`bmp` | **直接用 Read 工具读取**（模型可看图，无需 OCR） |
| 批量图片，或用户明确要求提取文字 | 走 MinerU 解析流程（图片按顺序合成一个文档处理） |
| 其他（txt、md、代码、json、csv 等） | 直接 Read，本技能不干预 |

多个文件混合输入时，对每个文件分别按扩展名选择解析方式。

## 解析流程

统一调用封装脚本 `scripts/parse.ps1`（脚本内置探测、缓存、批处理、清理、结果校验）：

```powershell
& "<本技能目录>\scripts\parse.ps1" -Paths <文件1> <文件2> ... [参数]
```

`<本技能目录>` 指当前 skill 的根目录（内含 `SKILL.md`、`scripts\`、`docs\`）。也可用相对路径：在技能根目录下执行 `& ".\scripts\parse.ps1"`。

### 参数

| 参数 | 说明 |
|---|---|
| `-Paths` | 输入文件绝对路径（可多个，批处理合并为一次 MinerU 调用，模型只加载一次） |
| `-OutDir` | 输出根目录。缺省时：单文件输出到源文件所在目录；多文件输出到临时目录并把 `.md` 复制回各自源目录 |
| `-Backend` | `auto`（默认）/ `hybrid-engine` / `pipeline` / `vlm-engine`。auto：总页数 < 10 选 pipeline，否则 hybrid-engine |
| `-Force` | 忽略缓存，强制重新解析 |
| `-KeepImages` | 保留 `images/` 目录（默认：输出在源目录时保留，临时目录时删除） |
| `-NoFormula` | 关闭公式识别（默认开启） |
| `-Method` | `auto`（默认）/ `txt` / `ocr`，仅 pipeline / hybrid 生效 |
| `-Lang` | OCR 语言，默认 `ch`，仅 pipeline 生效 |
| `-Effort` | `medium`（默认）/ `high`，仅 hybrid 生效，high 开启图表分析、更慢 |

### 超时设置

脚本会输出 `RECOMMENDED_TIMEOUT_SECONDS=NNN`。执行时 bash 命令超时应设为该值以上，避免默认 120s 截断。60 页基准约 83s（hybrid-engine）。

### 缓存

脚本检查 `<OutDir>/<文件名>/.../<文件名>.md`（或源目录下的同名 `.md`）是否比源文件新，命中则直接复用，不再调用 MinerU。需重新解析时用 `-Force`。

## 产物定位

脚本输出每行 `RESULT\t<源文件>\t<md路径>\t<字节>\t<行数>`。MinerU 内部结构为 `<OutDir>/<文件名>/<method>/<文件名>.md`（method 为 `auto`/`txt`/`ocr`/`hybrid_*`/`vlm`/`office`），脚本已递归定位并回传最终路径。

## 结果校验与上下文管理

- `WARNING_EMPTY`：产物小于 1KB，可能是空白/扫描失败，此时回退直接 Read 原文件
- `.md` 大于 2000 行：分块读取或先读开头摘要，避免撑爆上下文

## 清理

脚本自动删除除 `.md` 外的辅助文件（`images/` 按策略、`*_middle.json`、`*_content_list*.json`、`*_layout.pdf`、`*_span.pdf`、`*_model.json`、`*_origin.pdf` 等）。删除失败（如占用）则跳过，不阻塞。

## 首次使用与部署

首次使用（或任何一次解析报 `MINERU_UNAVAILABLE`）时，先运行检测：

```powershell
& "<本技能目录>\scripts\deploy.ps1" -Scan
```

- 输出 `DONE_MinerU_PRESENT`：本机已有 MinerU，直接继续解析
- 输出 `DONE_MinerU_ABSENT`：MinerU 未部署。扫描报告会给出硬件信息（GPU/VRAM/CPU/内存/磁盘/Python）与推荐部署方案

未部署时执行半自动安装（交互确认，用户可自定义安装目录与模型目录）：

```powershell
& "<本技能目录>\scripts\deploy.ps1" -Install [-MinerUDir <安装目录>] [-ModelDir <模型目录>] [-Backend GPU|CPU|auto]
```

安装完成后会生成 `mineru.config.json`（脚本同级目录），供 `parse.ps1` 定位。部署细节与故障排查见 `docs/DEPLOYMENT.md`。

## 失败回退

出现以下任一情况时，告知用户后回退到 Opencode 默认解析方式（直接 Read）：

- `MINERU_UNAVAILABLE`：MinerU 不可用（未部署或探测失败）。先跑 `deploy.ps1 -Scan` 确认，未部署则按「首次使用与部署」流程处理
- `MINERU_ERROR`：退出码非零
- `NO_MD`：未找到 `.md` 产物
- 解析耗时异常或用户明确要求停止

## 边界情况

- **路径含空格/中文**：PowerShell 调用运算符 `&` 并双引号包裹路径（脚本内部已处理）
- **只读场景**：脚本需写输出，若源目录禁止写入，显式传 `-OutDir` 到可写目录并告知用户
- **解析前已有同名 .md**：MinerU 会覆盖；脚本以最新产物为准

## 多 Harness 安装

本技能以单一 `SKILL.md` 为源，通过生成脚本为各 Agent Harness 生成原生副本（frontmatter/目录结构按各 harness 规范）：

```powershell
& "<本技能目录>\scripts\generate-harnesses.ps1" -Harness all [-Scope user|project] [-Force]
```

- `-Harness`：`all` 或逗号分隔列表（`opencode,claude,cline,codex,cherrystudio,gemini,zcode`）
- `-Scope`：`user`（用户级全局目录）或 `project`（当前项目目录）；未指定则交互询问
- `-TargetDir`：显式指定输出目录（调试用）
- 各 harness 支持情况与新增 harness 指南见 `docs/HARNESSES.md`

## 部署与故障排查

环境安装细节、GPU/CUDA 配置、CPU 降级方法见 `docs/DEPLOYMENT.md`；多 harness 适配见 `docs/HARNESSES.md`。
