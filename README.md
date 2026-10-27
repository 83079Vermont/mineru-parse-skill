# MinerU Parse Skill / MinerU 文档解析技能

[![MinerU](https://img.shields.io/badge/MinerU-4.0.12-blue)](https://github.com/opendatalab/MinerU)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Harnesses](https://img.shields.io/badge/harnesses-8-informational)](harnesses/registry.json)

**是什么**：把 PDF / DOCX / PPTX / XLSX / TIFF / 批量图片在**本机**解析成 Markdown，供 AI 编程 Agent 读入上下文的技能（**MinerU 4.0.12**，8 种 Harness 适配）。
**解决什么**：Agent 读不了二进制文档，云端解析又要上传文件。这里解析全程本地、文件不出本机，封装脚本负责缓存、批处理与结果校验。
**最快用上**：`& scripts\parse.ps1 -Paths D:\docs\paper.pdf`（WSL 用 `scripts/parse.sh`），产物路径看输出的 `RESULT` 行。

## 目录

- [一分钟上手](#一分钟上手)
- [适用格式](#适用格式)
- [质量档位与 auto 规则](#质量档位与-auto-规则)
- [parse 脚本参考](#parse-脚本参考)
- [输出标记与退出码](#输出标记与退出码)
- [产物与缓存](#产物与缓存)
- [本机部署现状](#本机部署现状)
- [首次部署](#首次部署)
- [Harness 支持](#harness-支持)
- [沙箱与资源](#沙箱与资源)
- [目录结构](#目录结构)
- [English](#english)

## 一分钟上手

已部署的机器上只有两步：解析 → 读产物。

```powershell
# Windows / DSH（多文件用逗号分隔，路径保持 Windows 写法 D:\...）
& "<技能目录>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"
& "<技能目录>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf","D:\docs\slides.pptx" -Tier standard
& "<技能目录>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf" -Pages "1-5,8" -Force
```

```bash
# WSL / Linux（多文件用空格分隔）
"<技能目录>/scripts/parse.sh" -Paths /mnt/d/docs/paper.pdf
"<技能目录>/scripts/parse.sh" -Paths a.pdf b.docx -Force
```

输出里找 `RESULT` 行，第 2 列是源文件、第 3 列就是产物路径：

```
RESULT	<源文件>	<产物路径>	<字节数>	<行数>
```

- 产物是单个自包含的 `.md`（图片内联为 base64），直接 Read 即可。
- 产物小于 1 KB 会额外打印 `WARNING_EMPTY`，此时回退直接读原文件。
- `.md` 超过 2000 行时分块读取，别整篇塞进上下文。
- 需要图片文件（`images/`）用 `-Format zip`；需要结构化 JSON 用 `-Format middle_json`。

没部署过（`MINERU_UNAVAILABLE`）→ 看[首次部署](#首次部署)。

## 适用格式

| 输入 | 处理 |
|---|---|
| `pdf` `docx` `pptx` `xlsx` `tif` `tiff` | `parse` 脚本 → MinerU → Markdown |
| 单张 `jpg` `jpeg` `png` `bmp` | 直接 Read（模型能看图，不必 OCR） |
| 批量图片，或要求提取图片文字 | 走 `parse`（多张按顺序合成一个文档处理） |
| `txt` `md` `json` `csv`、代码等 | 直接 Read，技能不介入 |

`parse` 脚本只接受上表 10 种扩展名，其余文件被静默跳过；全部不匹配时输出 `NO_SUPPORTED_FILES` 并以退出码 4 结束。混合输入时每个文件按各自扩展名选路。

## 质量档位与 auto 规则

| 档位 | 能力 | 依赖 |
|---|---|---|
| `flash` | 原生文本层解析 + 扫描件 Flash OCR | 不需要推理模型，最快 |
| `basic` | OCR、公式、表格（小模型） | 小模型，可纯 CPU |
| `standard` | 复杂版面（小模型 + VLM） | 另需 VLM 权重 |
| `advanced` | 更高精度（更多推理算力） | 同 `standard`，无需单独下载模型 |

`-Tier auto`（默认）的判定：

| 条件 | 结果 |
|---|---|
| 输入不全是 PDF（Office / 图片） | `flash` |
| 全是 PDF 且总页数 < 10 | `basic` |
| 全是 PDF 且总页数 ≥ 10 | `standard` |

- 判定针对**整次调用**：批处理里混进一个非 PDF，整批都走 `flash`。
- 页数由 venv 里的 `pypdfium2` 读取，非 PDF 记 1 页；读不到页码时按 1 页处理，会直接影响 `auto` 结果。

**文本型 PDF 不要用 `flash`**：flash 遇到公式页会把整页当图片内联成 base64，公式不可检索。同一份 3 页数学作业的实测产物：

| 档位 | 产物大小 | 行数 | 公式 |
|---|---|---|---|
| `flash` | 573 KB | 124 | 整页图片内联，不可检索 |
| `basic` | 3.6 KB | 186 | 还原为可读 LaTeX |

## parse 脚本参考

`.ps1` 与 `.sh` 参数同名同义，唯一区别是多文件分隔符（PowerShell 逗号，bash 空格）。

| 参数 | 取值 / 说明 |
|---|---|
| `-Paths` | 必填，输入文件绝对路径，可多个。**PowerShell 用逗号分隔** `-Paths a.pdf,b.docx`，bash 用空格分隔 |
| `-OutDir` | 输出根目录。缺省：单文件→源文件目录；多文件→临时目录，解析后复制回各自源目录 |
| `-Tier` | `auto`(默认) / `flash` / `basic` / `standard` / `advanced`，取代 3.x 的 `-Backend` |
| `-Pages` | PDF 页范围：`"1-5,8"` / `"r3-r1"`（`r1` 为末页）/ `all`；缺省为全部页 |
| `-Format` | `markdown`(默认) / `middle_json` / `zip`；`zip` 会落盘 `markdown.md` + `images/` + `middle_json.json` |
| `-OcrMode` | `auto`(默认) / `txt` / `ocr`，取代 3.x 的 `-Method` |
| `-NoImageAnalysis` | 关闭图像分析（近似取代 3.x 的 `-NoFormula`） |
| `-Force` | 忽略缓存，强制重新解析 |

3.x 旧参数仍被接受，打印 `WARN_DEPRECATED` 后自动映射或忽略，不会报错：

| 旧参数 | 4.0 行为 |
|---|---|
| `-Backend pipeline` | → `-Tier basic` |
| `-Backend hybrid-engine` / `vlm-engine` | → `-Tier standard` |
| `-Method <v>` | → `-OcrMode <v>` |
| `-Effort high` | → `-Tier advanced` |
| `-NoFormula` | → `-NoImageAnalysis` |
| `-KeepImages` | 已无对象：markdown 图片内联，没有 `images/` 目录可留；要图片文件用 `-Format zip` |
| `-Lang` | 4.0 已移除（OCR 语言自动），忽略 |

## 输出标记与退出码

脚本按行输出，便于 Agent 直接解析：

| 标记 | 含义 |
|---|---|
| `CACHED <源> <md>` | 命中缓存，未调用 MinerU |
| `PAGES <n> TIER=<t> FORMAT=<f>` | 总页数与**实际生效**的档位（`auto` 解析后的结果看这里） |
| `RECOMMENDED_TIMEOUT_SECONDS=NNN` | 建议超时，见下 |
| `RUNNING <源...> -> <目标>` | 即将执行的 MinerU 调用 |
| `RESULT <源> <产物> <字节> <行数>` | 成功；`zip` / `middle_json` 的行数列为 0 |
| `WARNING_EMPTY <源>` | `.md` 小于 1 KB，可能空白或扫描失败，回退直接读原文件 |
| `NO_MD <源>` | 未定位到产物 |
| `MINERU_ERROR <code>` | MinerU 退出码非零 |
| `MINERU_UNAVAILABLE` | 探测不到 MinerU |
| `NO_SUPPORTED_FILES` | 没有受支持的扩展名 |
| `DONE parsed=<n> cached=<m>` | 结束汇总 |

退出码：`0` 成功 · `3` MinerU 不可用 · `4` 无受支持文件 · `5` MinerU 报错。出现 `MINERU_UNAVAILABLE` / `MINERU_ERROR` / `NO_MD` 时应告知用户并回退到直接 Read。

**超时**：`RECOMMENDED_TIMEOUT_SECONDS = 30 + 页数 × 系数`，系数为 `flash` 3、`basic` 8、`standard`/`advanced` 15。调用方的命令超时要设为该值以上（DSH 的 `pwsh` 工具用 `timeoutMs`），否则默认 120 s 会截断。

## 产物与缓存

| 场景 | 产物位置 |
|---|---|
| 单文件 + `markdown` | `<OutDir>/<文件名>.md`（未传 `-OutDir` 则落在源文件目录） |
| 单文件 + `zip` / `middle_json` | `<OutDir>/<文件名>.zip` / `.json` |
| 多文件 | 临时目录解析后复制回各源文件目录（`<源文件目录>/<文件名>.md`） |

- **自包含**：`markdown` 是单个 `.md`，图片以 base64 data URI 内联，不产生 `images/` 等辅助目录。需要图片文件用 `-Format zip`。
- **缓存**：产物 `.md` 比源文件新即复用，打印 `CACHED` 且不再调用 MinerU；`-Force` 强制重解析。缓存判断只认 `.md`，`zip` / `middle_json` 产物不参与。
- **批处理**：多个文件先复制到临时目录（加序号前缀防重名），合并为**一次** `mineru-kit parse` 调用，模型只加载一次，解析完按源文件把产物复制回去。
- **只读源目录**：脚本需要写输出，源目录不可写时显式传 `-OutDir` 到可写目录；WSL 下 `/mnt/c`、`/mnt/d` 写入较慢，大文件建议输出到 WSL 本地目录。

## 本机部署现状

作者机器 Windows 与 WSL 两侧均已部署 MinerU **4.0.12**：

| 平台 | 安装根 | 解析入口 | 包与 VLM 引擎 | 配置 |
|---|---|---|---|---|
| Windows | `D:\MinerU` | `D:\MinerU\mineru-kit.bat` | `mineru[full]==4.0.12` + torch cu126 + LMDeploy | `D:\MinerU\config.yaml` |
| WSL | `~/MinerU` | `~/MinerU/mineru-kit.sh` | `mineru[torch]==4.0.12` + llama.cpp | `~/MinerU/config.yaml` |

- 同目录下的 `mineru.bat` / `mineru.sh` 是文档库入口，**解析一律走 `mineru-kit`**。
- 两侧配置相互独立：Windows 用 `mineru.config.json`，WSL 用 `scripts/mineru.config.linux.json`，可各自部署、互不干扰。WSL 内解析走 WSL 本地 MinerU（GPU 直通），不跨系统调 `D:\MinerU`。
- 本机已部署时不需要执行部署流程，只有解析报 `MINERU_UNAVAILABLE` 才需要下一节。

## 首次部署

检测（首次使用或报 `MINERU_UNAVAILABLE` 时先跑）：

```powershell
& "<技能目录>\scripts\deploy.ps1" -Scan
```

```bash
"<技能目录>/scripts/deploy.sh" --scan
```

- `DONE_MinerU_PRESENT`（退出码 0）：已部署，同时打印入口与版本
- `DONE_MinerU_ABSENT`（退出码 2）：未部署，打印 GPU / CPU / 内存 / 磁盘 / Python 扫描结果与推荐方案

未部署时安装：

```powershell
& "<技能目录>\scripts\deploy.ps1" -Install [-MinerUDir D:\MinerU] [-ModelDir D:\MinerU\models] [-Backend GPU|CPU|auto]
```

```bash
"<技能目录>/scripts/deploy.sh" --install --yes [--mineru-dir ~/MinerU] [--backend GPU|CPU|auto] [--mirror none]
```

`deploy.ps1` 逐项交互确认；`deploy.sh --yes` 全程非交互，适合 Agent 自动执行。退出码：`0` 完成 · `2` 未部署 · `3` 失败 · `4` 用户中止（`USER_ABORTED`）。

安装流程（4.0.12）：

| 步骤 | 内容 |
|---|---|
| 1 | 建 venv（Python 3.12；Linux 优先 `uv venv`） |
| 2 | 安装 `mineru[full]==4.0.12`（WSL 为 `mineru[torch]==4.0.12`） |
| 3 | GPU torch：Windows 装 `torch==2.12.1` + `torchvision==0.27.1` 的 cu126 轮子；Linux 在 CUDA 不可用时用 `--torch-backend=cu126` 重装 |
| 4 | Windows GPU 额外建 `cuda_stub` junction → `torch\lib`（LMDeploy turbomind 通过 `CUDA_PATH` 找 CUDA DLL）；GPU 场景可把 CPU 版 `onnxruntime` 换成 `onnxruntime-gpu` —— 注意 4.0.12 起 `onnxruntime` 是**必需依赖**，升级 mineru 后会重新带回 CPU 版，两者共用同一包目录会互相覆盖（详见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)「onnxruntime」一节） |
| 5 | 写 `config.yaml`（`model.source: modelscope`、`model.base_dir`、`small_backend: torch`、`vlm.engine`） |
| 6 | `mineru-kit models download --tier standard --source modelscope` → `models verify` |
| 7 | 写 `mineru.bat` / `mineru-kit.bat`（WSL 为 `.sh`）与技能定位配置 |

国内网络：

| 资源 | 用这个 | 说明 |
|---|---|---|
| PyPI | `https://mirrors.cloud.tencent.com/pypi/simple` | `deploy.ps1` 安装时询问；`deploy.sh` 默认使用，`--mirror none` 关闭 |
| torch cu126 轮子 | `https://mirror.sjtu.edu.cn/pytorch-wheels/cu126` | `download.pytorch.org` 实测约 0.1 MB/s，SJTU 约 15 MB/s |
| 模型权重 | `--source modelscope` | HuggingFace 走 Xet 卡住时设 `HF_HUB_DISABLE_XET=1` |

> `deploy.sh --win-models` 仍被接受，但在 4.0 下无效果：4.x 使用新的模型包（`MinerU-4_models_torch`/`_onnx` + GGUF/LMDeploy VLM），3.x 的 Windows 模型目录不能复用。

解析脚本如何找到 MinerU：

```
Windows: MINERU_KIT_BAT → mineru.config.json:mineruKitBat → mineru.bat 同目录的 mineru-kit.* → PATH
Linux  : MINERU_KIT_BIN → mineru.config.linux.json:mineruKitBin → mineru 同目录的 mineru-kit → PATH
```

Windows 还要求先找到 `mineru.bat`（`MINERU_BAT` → 配置项 `mineruBat` → `D:\MinerU\mineru.bat` → PATH 的 `mineru`），找不到会直接 `MINERU_UNAVAILABLE`，即使 `mineru-kit` 在 PATH 上。配置文件可放在脚本同级、技能根目录或 `~/.config/mineru/`。

仓库里只有模板，本机配置由 `deploy` 生成且已 gitignore：

```
mineru.config.example.json               # Windows: mineruBat / mineruKitBat / venvPython / mineruHome
scripts/mineru.config.linux.example.json # WSL: mineruBin / mineruKitBin / venvPython / modelsDir / mineruHome
```

### 从仓库安装

仓库根目录即技能根目录（`SKILL.md` 在顶层），clone 到位即被 Harness 识别：

```bash
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.dsh/skills/mineru-parse               # DSH（用户级）
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.config/opencode/skills/mineru-parse   # OpenCode（用户级）
git clone https://github.com/83079Vermont/mineru-parse-skill.git ~/.claude/skills/mineru-parse            # Claude Code / Cherry Studio
```

Windows 下把 `~` 换成 `%USERPROFILE%`。clone 后仍需用 `deploy -Scan` 确认本机 MinerU 可用，并按需生成定位配置。

## Harness 支持

单一 `SKILL.md` 是权威源；`scripts/generate-harnesses.ps1` 读取 `harnesses/registry.json`，按各 Harness 规范生成带 frontmatter 的原生副本（连同 `scripts/`、`docs/`）：

| Harness | 状态 | 用户级目录 | 项目级目录 |
|---|---|---|---|
| OpenCode | native | `~/.config/opencode/skills/mineru-parse` | `.opencode/skills/mineru-parse` |
| Claude Code | native | `~/.claude/skills/mineru-parse` | `.claude/skills/mineru-parse` |
| Cline | native | `~/.cline/skills/mineru-parse` | `.cline/skills/mineru-parse` |
| Codex | native | `~/.codex/skills/mineru-parse` | `.codex/skills/mineru-parse` |
| Gemini | native（TOML） | `~/.gemini/skills/mineru-parse` | `.gemini/skills/mineru-parse` |
| DSH | native | `~/.dsh/skills/mineru-parse` | `.dsh/skills/mineru-parse` |
| Cherry Studio | compatible（复用 Claude） | `~/.claude/skills/mineru-parse` | `.claude/skills/mineru-parse` |
| Zcode | extension-point | `~/.zcode/skills/mineru-parse` | `.zcode/skills/mineru-parse` |

```powershell
& "<技能目录>\scripts\generate-harnesses.ps1" -Harness all -Scope user [-Force]    # 全部 8 个
& "<技能目录>\scripts\generate-harnesses.ps1" -Harness opencode,claude -Scope project
& "<技能目录>\scripts\generate-harnesses.ps1" -Harness claude -TargetDir D:\tmp\test  # 只预览输出
```

- `-Scope` 省略时会交互询问 user / project；项目级副本优先级高于用户级（DSH 按 rank 扫描）。
- 新增 Harness 只需在 `harnesses/registry.json` 加一条，详见 [docs/HARNESSES.md](docs/HARNESSES.md)。

## 沙箱与资源

| 现象 | 原因 / 处理 |
|---|---|
| `PermissionError: [WinError 5]`（`multiprocessing` / `ProcessPoolExecutor`） | DSH Windows 沙箱禁止创建命名管道，PDF 渲染进程池需要它。改 `-Tier flash`（flash 不需要模型进程池），或在沙箱外的普通终端执行 |
| `<tmp>/mineru-api-client-*/output` 创建失败（Access denied） | 沙箱下 `os.mkdir(path, mode)` 会建出不可访问的目录。`scripts/sandbox/sitecustomize.py` 去掉 `mode` 参数，`parse.ps1` 通过 `PYTHONPATH` 自动注入，无需手工操作 |
| 显存不足（OOM） | RTX 4060 只有 8 GB：`standard`/`advanced` 需要 VLM，长文档分批解析（减少单次 `-Paths` 数量，或用 `MINERU_PROCESSING_WINDOW_SIZE` 调小处理窗口），必要时降 `-Tier basic` / `flash` |
| 想降到 CPU | 4.0 没有 `MINERU_DEVICE_MODE`：设 `MINERU_MODEL_SMALL_BACKEND=onnx`、`MINERU_TABLE_DEVICE=cpu` |
| uv 说版本已满足但没换 wheel | PEP 440 下 `torch==2.12.1` 会匹配 `2.12.1+cpu`，加 `--reinstall` 或直接装本地 wheel |

性能实测（WSL，含冷启动）：`flash` 单页文档约 1.7 s，`basic` 单页约 9.7 s，`standard` 单页约 15.5 s（峰值内存约 3.9 GB）。

部署环境、3.x→4.0 配置映射与更多排查见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

## 目录结构

```
mineru-parse/
├── SKILL.md                    # 权威技能源（OpenCode 原生格式，其余 Harness 由它生成）
├── README.md                   # 本文档
├── LICENSE                     # MIT
├── mineru.config.example.json  # Windows 定位配置模板
├── scripts/
│   ├── parse.ps1               # 解析封装（Windows）：缓存 / 批处理 / 校验
│   ├── parse.sh                # 解析封装（Linux/WSL）：参数与输出标记同 .ps1
│   ├── deploy.ps1              # 检测 / 硬件扫描 / 半自动安装（Windows）
│   ├── deploy.sh               # 检测 / 硬件扫描 / uv 安装（Linux/WSL）
│   ├── generate-harnesses.ps1  # 多 Harness 副本生成器
│   ├── mineru.config.linux.example.json
│   └── sandbox/
│       └── sitecustomize.py    # DSH 沙箱临时目录权限修复（parse.ps1 自动注入）
├── harnesses/
│   └── registry.json           # Harness 注册表
└── docs/
    ├── DEPLOYMENT.md           # 部署环境、3.x→4.0 映射、故障排查
    └── HARNESSES.md            # 多 Harness 适配与新增 Harness
```

## English

**Overview** — `mineru-parse` turns local PDF / DOCX / PPTX / XLSX / TIFF and image batches into Markdown so AI coding agents can read them. Parsing is fully local (no upload), wrapped by scripts that add caching, batching and result validation. Requires a local MinerU **4.0.12** install.

**Quick start**

```powershell
& "<skill-dir>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf"
& "<skill-dir>\scripts\parse.ps1" -Paths "D:\docs\paper.pdf","D:\docs\slides.pptx" -Tier standard -Force
```

```bash
"<skill-dir>/scripts/parse.sh" -Paths /mnt/d/docs/paper.pdf
"<skill-dir>/scripts/parse.sh" -Paths a.pdf b.docx -Force
```

Read the `RESULT` line: `RESULT <source> <artifact> <bytes> <lines>`. Output under 1 KB also prints `WARNING_EMPTY` — fall back to reading the source. Not installed yet? `scripts/deploy.ps1 -Scan` (Windows) or `scripts/deploy.sh --scan` (WSL/Linux) prints a hardware report and either `DONE_MinerU_PRESENT` or `DONE_MinerU_ABSENT` (exit code 2); `-Install` / `--install --yes` installs MinerU 4.0.12.

**CLI reference** — `-Paths` (required), `-OutDir`, `-Tier auto|flash|basic|standard|advanced`, `-Pages "1-5,8"`, `-Format markdown|middle_json|zip`, `-OcrMode auto|txt|ocr`, `-NoImageAnalysis`, `-Force`. Names are identical in `.ps1` and `.sh`; separate multiple files with commas (PowerShell) or spaces (bash). `auto` resolves to `flash` for non-PDF input, `basic` for PDFs under 10 pages, otherwise `standard` — never choose `flash` for text PDFs, it inlines whole pages as images and formulas stop being searchable. Markdown output is self-contained (images inlined as base64); use `-Format zip` for image files. Legacy 3.x flags (`-Backend`, `-Method`, `-Effort`, `-NoFormula`, `-Lang`) are still accepted and mapped with a `WARN_DEPRECATED` line. Full parameter table: see the Chinese reference above.

**Harnesses** — one authoritative `SKILL.md`; `scripts/generate-harnesses.ps1 -Harness all -Scope user` generates native copies for OpenCode, Claude Code, Cline, Codex, Gemini, DSH, Cherry Studio (reuses the Claude layout) and Zcode (extension point). See [docs/HARNESSES.md](docs/HARNESSES.md).

## License / 许可

[MIT](LICENSE) — 可自由使用、修改与再分发。
