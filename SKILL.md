---
name: mineru-parse
description: 使用本地 MinerU 4.0 解析文档（DSH/Windows 用 parse.ps1，WSL/Linux 用 parse.sh）。当用户输入或附带 PDF、DOCX、PPTX、XLSX、TIFF/TIF 或批量图片（jpg/jpeg/png/bmp/tif/tiff）文件时，默认调用 MinerU 将其解析为 Markdown 再读取；单张 jpg/jpeg/png/bmp 图片直接用 Read 工具读取；其他格式使用 DSH 默认解析。触发词：mineru、pdf、docx、pptx、xlsx、tiff、解析、parse、parse_docs。
---

# MinerU 文档解析

> 本技能面向 **MinerU 4.0**（`mineru-kit` CLI）。如果解析报参数错误，先用
> `mineru-kit parse --help` 核对当前安装的 CLI 契约（4.0 与 3.x 参数完全不同）。

当用户向 DSH 输入文件时，按扩展名（不区分大小写）选择解析方式：

## 格式判定

| 类型 | 处理方式 |
|---|---|
| `pdf`, `docx`, `pptx`, `xlsx`, `tif`, `tiff` | 走 MinerU 解析流程 |
| 单张 `jpg`/`jpeg`/`png`/`bmp` | **直接用 Read 工具读取**（模型可看图，无需 OCR） |
| 批量图片，或用户明确要求提取文字 | 走 MinerU 解析流程（图片按顺序合成一个文档处理） |
| 其他（txt、md、代码、json、csv 等） | 直接 Read，本技能不干预 |

多个文件混合输入时，对每个文件分别按扩展名选择解析方式。

## 解析流程

**DSH 跑在 Windows，默认一律用 PowerShell 版 `parse.ps1`**（脚本内置探测、缓存、批处理、清理、
结果校验，与 bash 版行为及输出标记完全一致）：

```powershell
& "C:\Users\wanji\.dsh\skills\mineru-parse\scripts\parse.ps1" -Paths <文件1>,<文件2> [参数]
```

> **多个文件必须用逗号分隔**（PowerShell 数组语法）：`-Paths a.pdf,b.docx`。
> 写成 `-Paths a.pdf b.docx` 会报「找不到接受自变量的位置参数」——这是 PowerShell 的参数绑定规则，
> 不是脚本缺陷。bash 版 `parse.sh` 则用空格分隔：`-Paths a.pdf b.docx`。

路径直接用 Windows 写法（`D:\a\b.pdf` 或 `D:/a/b.pdf`），**不要**转成 `/mnt/d/...`。

只有在明确要走 WSL 本地 MinerU 时才用 bash 版：

```bash
wsl.exe -d Ubuntu-26.10 -- bash /mnt/c/Users/wanji/.dsh/skills/mineru-parse/scripts/parse.sh \
    -Paths /mnt/d/docs/paper.pdf [参数]
```

`<本技能目录>` 指当前 skill 的根目录 `C:\Users\wanji\.dsh\skills\mineru-parse`（内含 `SKILL.md`、
`scripts/`、`docs/`）。**本机两侧均已部署 MinerU 4.0**：

| 平台 | 安装根 | 解析入口 | 配置 |
|---|---|---|---|
| Windows | `D:\MinerU` | `D:\MinerU\mineru-kit.bat` | `D:\MinerU\config.yaml`（`MINERU_CONFIG`） |
| WSL | `~/MinerU` | `~/MinerU/mineru-kit.sh` | `~/MinerU/config.yaml` |

技能目录下的 `mineru.config.json` / `scripts/mineru.config.linux.json` 已指向它们，通常无需再走部署流程。

### 参数

| 参数 | 说明 |
|---|---|
| `-Paths` | 输入文件绝对路径（可多个，批处理合并为一次 MinerU 调用，模型只加载一次）。**PowerShell 用逗号分隔**（`-Paths a.pdf,b.docx`），bash 用空格分隔 |
| `-OutDir` | 输出根目录。缺省时：单文件输出到源文件所在目录；多文件输出到临时目录并把产物复制回各自源目录 |
| `-Tier` | `auto`（默认）/ `flash` / `basic` / `standard` / `advanced`，取代 3.x 的 `-Backend` |
| `-Pages` | PDF 页范围，如 `1-5,8` / `r3-r1`（`r1` 为末页）/ `all`；缺省为 MinerU 默认（全部页） |
| `-Format` | `markdown`（默认）/ `middle_json` / `zip`；`zip` 会落盘 `markdown.md` + `images/` + `middle_json.json` |
| `-OcrMode` | `auto`（默认）/ `txt` / `ocr`，取代 3.x 的 `-Method` |
| `-NoImageAnalysis` | 关闭图像分析（近似取代 3.x 的 `-NoFormula`） |
| `-Force` | 忽略缓存，强制重新解析 |

**档位语义（4.0）**

| 档位 | 用途 | 依赖 |
|---|---|---|
| `flash` | 原生文本层解析 + 扫描件 Flash OCR | 无需推理模型，最快 |
| `basic` | OCR、公式、表格（小模型） | 小模型；可纯 CPU |
| `standard` | 复杂版面（小模型 + VLM） | 还需 VLM 权重 |
| `advanced` | 更高精度（更多推理算力） | 同 standard，无需单独下载模型 |

`-Tier auto` 的选择规则：非 PDF（Office/图片）→ `flash`；PDF 且总页数 < 10 → `basic`；否则 `standard`。

> **为什么 PDF 默认不用 flash**：flash 对带公式的 PDF 会把整页当图片内联成 base64，
> 实测 `Homework9.pdf`（3 页数学作业）flash 产物 **573 KB / 124 行** 且公式不可检索，
> 而 `basic` 产物 **3.6 KB / 186 行**，公式还原为可读 LaTeX。文本型 PDF 一律用 `basic`。

**已废弃的 3.x 参数**（仍被接受，会打印 `WARN_DEPRECATED` 并自动映射，不会报错）：
`-Backend`（pipeline→basic、hybrid-engine/vlm-engine→standard）、`-Method`（→`-OcrMode`）、
`-Effort high`（→`advanced`）、`-NoFormula`（→`-NoImageAnalysis`）、`-KeepImages`（4.0 markdown
会把图片内联为 base64，已无 `images/` 目录可留；要图片文件请用 `-Format zip`）、`-Lang`（4.0 已移除，
OCR 语言自动，忽略）。

### 超时设置

脚本会输出 `RECOMMENDED_TIMEOUT_SECONDS=NNN`（flash 约 30+3×页数、basic 30+8×页数、
standard/advanced 30+15×页数）。执行时命令超时应设为该值以上（`pwsh` 工具用 `timeoutMs`），
避免默认 120s 截断。实测（WSL，含冷启动）：flash 单文件约 1.7s、basic 单页约 9.7s、
standard 单页约 15.5s。

### 缓存

脚本检查 `<OutDir>/<文件名>.md` 或源目录下的同名 `.md` 是否比源文件新，命中则直接复用，不再调用
MinerU。需重新解析时用 `-Force`。

### MinerU 定位链

- Windows（`parse.ps1`）：环境变量 `MINERU_KIT_BAT` → 脚本同级 `mineru.config.json` 的 `mineruKitBat`
  → `mineru.bat` 同目录的 `mineru-kit.bat`/`.cmd`/`.exe` → PATH 中 `mineru-kit`
- Linux/WSL（`parse.sh`）：环境变量 `MINERU_KIT_BIN` → 脚本同级 `mineru.config.linux.json` 的
  `mineruKitBin` → `mineru` 同目录的 `mineru-kit` → PATH 中 `mineru-kit`

两份配置文件相互独立（`.json` / `.linux.json`），Windows 与 WSL 可各自部署、互不干扰。在 WSL 中解析走 WSL 本地 MinerU（GPU 直通），不跨系统调用 `D:\MinerU`。

## 产物定位

脚本输出每行 `RESULT\t<源文件>\t<产物路径>\t<字节>\t<行数>`。

MinerU 4.0 的产物规则（已实测）：

| 场景 | `-o` 语义 | 结果 |
|---|---|---|
| 单文件 + `markdown` | 指向具体文件 | `<OutDir>\<文件名>.md` |
| 单文件 + `zip`/`middle_json` | 指向目录 | `<OutDir>\<文件名>.zip` / `.json` |
| 目录/多文件输入 | 指向目录 | `<OutDir>\<每个文件名>.md` |

markdown 形态是**单文件自包含**的：图片以 base64 data URI 内联，不产生 `images/` 等辅助文件
（因此 3.x 时代「删除中间产物」的清理逻辑已无对象）。需要把图片单独落盘时用 `-Format zip`。

## 结果校验与上下文管理

- `WARNING_EMPTY`：产物小于 1KB，可能是空白/扫描失败，此时回退直接 Read 原文件
- `.md` 大于 2000 行：分块读取或先读开头摘要，避免撑爆上下文
- `NO_MD`：未定位到产物，视为失败

## 沙箱与资源注意

- **命名管道**：DSH 的 Windows 沙箱禁止进程创建命名管道，MinerU 内部使用
  `ProcessPoolExecutor`（PDF 渲染）时会报 `WinError 5`。本技能已在 `scripts/sandbox/` 放置
  `sitecustomize.py` 修复临时目录问题（`os.mkdir(path, mode)` 在沙箱下会产生不可访问目录），
  `parse.ps1` 会自动通过 `PYTHONPATH` 注入。若某个档位仍在沙箱内因管道失败，改用 `-Tier flash`
  （无需模型进程池），或在工作区外的普通终端里运行。
- **显存**：RTX 4060 只有 8GB。`standard`/`advanced` 需要 VLM，长文档请分批解析；显存不足时降级
  `-Tier basic`。

## 首次使用与部署

**本机 Windows 与 WSL 两侧均已部署 MinerU 4.0**（`D:\MinerU\mineru-kit.bat`、
`~/MinerU/mineru-kit.sh` 均存在，技能配置已指向它们），正常情况下不需要执行本节。仅当解析报
`MINERU_UNAVAILABLE` 时，先按平台运行检测：

```powershell
& "<本技能目录>\scripts\deploy.ps1" -Scan          # Windows
```

```bash
"<本技能目录>/scripts/deploy.sh" --scan            # Linux / WSL / macOS
```

- 输出 `DONE_MinerU_PRESENT`：本机已有 MinerU，直接继续解析
- 输出 `DONE_MinerU_ABSENT`：MinerU 未部署。扫描报告会给出硬件信息（GPU/VRAM/CPU/内存/磁盘/Python）与推荐部署方案

未部署时执行半自动安装（交互确认；加 `--yes` 全程非交互，供 Agent 自动执行）：

```powershell
& "<本技能目录>\scripts\deploy.ps1" -Install [-MinerUDir <安装目录>] [-ModelDir <模型目录>] [-Backend GPU|CPU|auto]
```

```bash
"<本技能目录>/scripts/deploy.sh" --install --yes [--mineru-dir ~/MinerU] [--backend GPU|CPU|auto]
```

4.0 安装流程：`uv venv`（Python 3.12）→ `uv pip install "mineru[full]==4.0.10"`
（Linux 用 `mineru[torch]` + llama.cpp 亦可；Windows 的 `[full]` 走 LMDeploy）→
GPU torch（Windows 走 cu126，**当前 download.pytorch.org 在国内极慢，用 SJTU 镜像**）→
`mineru-kit models download --tier standard --source modelscope` →
`mineru-kit models verify` → 生成 `config.yaml`、`mineru.bat`/`mineru-kit.bat`（Windows）或
`mineru.sh`/`mineru-kit.sh`（WSL）与技能配置。

安装完成后会生成 `mineru.config.json`（Windows）或 `mineru.config.linux.json`（WSL/Linux），
供对应 parse 脚本定位。部署细节与故障排查见 `docs/DEPLOYMENT.md`。

## 失败回退

出现以下任一情况时，告知用户后回退到 DSH 默认解析方式（直接 Read）：

- `MINERU_UNAVAILABLE`：MinerU 不可用（未部署或探测失败）。先跑对应平台的 `deploy -Scan`/`deploy.sh --scan` 确认，未部署则按「首次使用与部署」流程处理
- `MINERU_ERROR`：退出码非零
- `NO_MD`：未找到 `.md` 产物
- 解析耗时异常或用户明确要求停止

## 边界情况

- **路径含空格/中文**：Windows 用 `&` 调用运算符并双引号包裹路径；Linux/WSL 用双引号包裹路径（脚本内部均已处理）
- **DSH 下路径**：直接用 `D:\x\y.pdf`，不要转成 `/mnt/d/x/y.pdf`（那会让 `parse.ps1` 找不到文件）；只有走 `wsl.exe ... parse.sh` 时才转成 `/mnt/d/...`
- **只读场景**：脚本需写输出，若源目录禁止写入，显式传 `-OutDir` 到可写目录并告知用户。注意 WSL 下 `/mnt/c`、`/mnt/d` 属 drvfs，大文件写入较慢，建议输出到 WSL 本地目录
- **解析前已有同名 .md**：MinerU 会覆盖；脚本以最新产物为准

## 多 Harness 安装

本技能以单一 `SKILL.md` 为源，通过生成脚本为各 Agent Harness 生成原生副本（frontmatter/目录结构按各 harness 规范）：

```powershell
& "<本技能目录>\scripts\generate-harnesses.ps1" -Harness all [-Scope user|project] [-Force]
```

- `-Harness`：`all` 或逗号分隔列表（`opencode,claude,cline,codex,cherrystudio,gemini,zcode,dsh`）
- `-Scope`：`user`（用户级全局目录）或 `project`（当前项目目录）；未指定则交互询问
- `-TargetDir`：显式指定输出目录（调试用）
- 各 harness 支持情况与新增 harness 指南见 `docs/HARNESSES.md`
- OpenCode 的全局技能目录是 `~/.config/opencode/skills/<name>/SKILL.md`（本机已同步一份 `mineru-parse`）
- WSL/Linux 下无 PowerShell 时，可直接把技能目录复制/软链到目标 harness 的 skills 目录（脚本两平台 .ps1/.sh 均已随带）

## 部署与故障排查

环境安装细节、GPU/CUDA 配置、CPU 降级方法见 `docs/DEPLOYMENT.md`；多 harness 适配见 `docs/HARNESSES.md`。
