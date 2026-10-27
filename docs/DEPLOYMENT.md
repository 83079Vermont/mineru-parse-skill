# MinerU 部署环境、迁移与故障排查

本技能面向 **MinerU 4.0**（`mineru-kit` CLI）。日常解析只需调用 `scripts/parse.ps1`（Windows）或
`scripts/parse.sh`（Linux/WSL）；对应的 `deploy` 脚本负责首次检测与半自动部署。

## 一、4.0 与 3.x 的关键差异

| 维度 | 3.x | 4.0 |
|---|---|---|
| 解析入口 | `mineru -p <in> -o <out> -b <backend>` | `mineru-kit parse <in> -o <out> --tier <tier>` |
| 文档库入口 | —— | `mineru`（`parse`/`read`/`find`/`search`/`server` 等命令族） |
| 质量选择 | `-b pipeline/hybrid-engine/vlm-engine` | `--tier flash/basic/standard/advanced` |
| OCR 方式 | `-m auto/txt/ocr` | `--ocr-mode auto/txt/ocr` |
| OCR 语言 | `-l ch` | 已移除（自动） |
| 公式开关 | `-f False` | `--disable-image-analysis`（近似） |
| 配置文件 | `mineru.json`（`MINERU_TOOLS_CONFIG_JSON`） | `$MINERU_HOME/config.yaml`（`MINERU_CONFIG`） |
| 设备选择 | `MINERU_DEVICE_MODE=cuda/cpu` | 已移除；由 `model.small_backend` + `model.vlm.engine` 决定 |
| 依赖分组 | `mineru[core]` / `mineru[pipeline]` / `mineru[vlm]` | 基础包 / `mineru[torch]` / `mineru[full]` |
| 模型 | pipeline 小模型目录 + MinerU2.5-Pro safetensors | `MinerU-4_models_torch`/`_onnx` 包 + GGUF/LMDeploy VLM |
| 模型下载 | `python -m mineru.cli.models_download -s modelscope -m all` | `mineru-kit models download --tier standard --source modelscope` |
| markdown 产物 | `<out>/<stem>/<method>/<stem>.md` + `images/` | 单个自包含 `.md`（图片内联 base64）；`--format zip` 才有 `images/` |
| HTTP API | `/file_parse`、`/tasks` | V1：`/v1/uploads`、`/v1/parse/jobs`、`/v1/files` |

## 二、当前部署环境

两侧当前均为 **4.0.12**（2026-10-27 由 4.0.10 升级）；3.x 与 4.0.10 环境都以改名方式保留，可随时回滚。

### Windows

- 安装位置：`D:\MinerU`
- 虚拟环境：`D:\MinerU\.venv`（Python 3.12.10）
- MinerU：`4.0.12`（`mineru[full]`），`lmdeploy 0.17.0`，`docvortex 0.6.5`
- torch：`2.12.1+cu126`（CUDA 12.6；`lmdeploy` 0.17 要求 `torch<=2.12.1`）
- 配置：`D:\MinerU\config.yaml`
- 包装脚本：`mineru.bat`（文档库）、**`mineru-kit.bat`（解析，技能使用）**
- 模型：`D:\MinerU\models\v4`
- `D:\MinerU\cuda_stub`：junction → `.venv\Lib\site-packages\torch\lib`（LMDeploy turbomind 需要 `CUDA_PATH` 存在）
- GPU：RTX 4060 Laptop 8GB，驱动 617.14

### WSL（Ubuntu-26.10，用户 wsl1）

- 安装位置：`/home/wsl1/MinerU`
- 虚拟环境：`/home/wsl1/MinerU/.venv`（Python 3.12.14，uv 管理）
- MinerU：`4.0.12`（`mineru[torch]`），`docvortex 0.6.5`，VLM 引擎 **llama.cpp**（`mineru-llama-cpp 0.1.2`）
- torch：`2.14.1+cu130`（Linux PyPI wheel 自带 CUDA，`torch.cuda.is_available()=True`）
- 配置：`/home/wsl1/MinerU/config.yaml`
- 包装脚本：`mineru.sh`（文档库）、**`mineru-kit.sh`（解析）**
- 模型：`/home/wsl1/MinerU/models`（`MinerU-4_models_torch` + `MinerU2.5-Pro-2605-1.2B-GGUF`，共约 2.0 GB）
- GPU 直通：`/dev/dxg` + nvidia-smi 可见 RTX 4060

### 4.0.10 → 4.0.12 升级记录（2026-10-27）

| 平台 | 升级命令（国内源） | 结果 |
|---|---|---|
| Windows | `uv pip install "mineru[full]==4.0.12" --index-url https://mirrors.cloud.tencent.com/pypi/simple --extra-index-url https://mirror.sjtu.edu.cn/pytorch-wheels/cu126` | 变更 6 包，7.3 s |
| WSL | `python -m pip install --upgrade "mineru[torch]==4.0.12" -i https://mirrors.cloud.tencent.com/pypi/simple` | 变更 5 包 |

- 依赖变化：`docvortex 0.5.11 → 0.6.5`，新增 `fastapi-offline`、`mineru-magika`、
  `onnxruntime`（CPU 版）与 `onnxruntime-directml`；`torch`（Windows `2.12.1+cu126` / WSL `2.14.1+cu130`）、
  `lmdeploy 0.17.0`、`transformers 5.19.0` 均未被改动。
- 模型权重无变更，不需要重新下载。
- Windows 侧升级前卸载了 `onnxruntime-gpu 1.30.0`（原因见下方「onnxruntime 不能共存」）。
- 校验：`uv pip check` 165 个包全部兼容；basic 档解析 87 页数学 PDF 的第 5–6 页产出
  7157 B / 121 行，**Windows 与 WSL 产物字节一致**；standard（VLM）档两侧均正常出产物。
- 备份：`D:\MinerU\.venv-4.0.10.bak`（5.36 GB）、`~/MinerU/.venv-4.0.10.bak`（6.2 GB），
  依赖清单 `requirements-4.0.10.lock` / `requirements-4.0.12.lock`。

### 回滚产物与步骤

| 平台 | venv 备份 | 依赖清单 | 配置备份 |
|---|---|---|---|
| Windows | `D:\MinerU\.venv-4.0.10.bak`（回 4.0.10）<br>`D:\MinerU\.venv-3.4.5.bak`（回 3.4.5） | `requirements-4.0.10.lock` / `requirements-4.0.12.lock` | `D:\MinerU\_backup-3.4.5\{mineru.json,mineru.bat,pip-freeze-3.4.5.txt,...}` |
| WSL | `~/MinerU/.venv-4.0.10.bak`<br>`~/MinerU/.venv-3.4.5.bak` | 同上 | `~/MinerU/_backup-3.4.5/{mineru.json,mineru.sh,pip-freeze-3.4.5.txt,...}` |

**回滚到 4.0.10（Windows 示例）**：

```powershell
Rename-Item 'D:\MinerU\.venv' 'D:\MinerU\.venv-4.0.12'
Rename-Item 'D:\MinerU\.venv-4.0.10.bak' '.venv'
```

**回滚到 3.4.5**：

```powershell
Rename-Item 'D:\MinerU\.venv' 'D:\MinerU\.venv-4.0.12'
Rename-Item 'D:\MinerU\.venv-3.4.5.bak' '.venv'
Copy-Item 'D:\MinerU\_backup-3.4.5\mineru.json' 'D:\MinerU\mineru.json' -Force
Copy-Item 'D:\MinerU\_backup-3.4.5\mineru.bat'  'D:\MinerU\mineru.bat'  -Force
# 技能侧配置同步回退到 3.x 版本（mineru.config.json 去掉 mineruKitBat）
```

WSL 同理（`mv .venv .venv-4.0.12; mv .venv-4.0.10.bak .venv`，还原 `mineru.json`/`mineru.sh`）。

## 三、3.x → 4.0 配置映射

| 3.x | 4.0 | 说明 |
|---|---|---|
| `models-dir.pipeline` | `model.base_dir` | 指向新的 4.0 模型根 |
| `models-dir.vlm` | `model.vlm.engine` | 3.x 的 VLM 目录不再使用，改由引擎从 4.0 仓库取权重 |
| `model-source: local` | `model.source: local` | 运行时离线；下载时临时用 `--source modelscope` |
| `MINERU_TOOLS_CONFIG_JSON` | `MINERU_HOME` + `MINERU_CONFIG` | 4.0 读 config.yaml |
| `MINERU_DEVICE_MODE=cuda` | —— | 移除；GPU 由 `small_backend: torch` + VLM 引擎体现 |
| `CUDA_PATH=<cuda_stub>` | 保留（仅 GPU + LMDeploy） | turbomind 通过它找 CUDA DLL |
| `latex-delimiter-config` | 未迁移 | 4.0 config.yaml 无对应字段；数学定界符由渲染器决定 |
| `llm-aided-config` | `llm_aided.*` | 保持 `enable: false`，不复制占位 api_key |
| `bucket_info` | 丢弃 | S3 占位，未使用 |

## 四、安装流程（deploy 脚本）

**检测**：

```powershell
& scripts\deploy.ps1 -Scan          # Windows
```
```bash
scripts/deploy.sh --scan            # Linux / WSL
```

- `DONE_MinerU_PRESENT`：已部署，输出入口路径与版本（`mineru version --json`）
- `DONE_MinerU_ABSENT`：未部署，输出硬件扫描与推荐方案

**安装**：

```powershell
& scripts\deploy.ps1 -Install [-MinerUDir <目录>] [-ModelDir <目录>] [-Backend GPU|CPU|auto]
```
```bash
scripts/deploy.sh --install --yes [--mineru-dir ~/MinerU] [--backend GPU|CPU|auto]
```

4.0 流程：`uv venv`（Python 3.12）→ `mineru[full]==4.0.12`（Linux 用 `mineru[torch]`）→
GPU torch（Windows：cu126，优先 SJTU 镜像）→ 建 `cuda_stub` junction →
写 `config.yaml` → `mineru-kit models download --tier standard --source modelscope` +
`models verify` → 写 `mineru.bat`/`mineru-kit.bat`（或 `.sh`）与技能配置。

**MinerU 定位链**：Windows `MINERU_KIT_BAT` → `mineru.config.json:mineruKitBat` →
`mineru.bat` 同目录的 `mineru-kit.*` → PATH；Linux `MINERU_KIT_BIN` →
`mineru.config.linux.json:mineruKitBin` → `mineru` 同目录的 `mineru-kit` → PATH。

## 五、故障排查

### 沙箱禁止命名管道（DSH Windows）

现象：解析中途 `PermissionError: [WinError 5]` 出现在 `multiprocessing.connection` /
`ProcessPoolExecutor` / `_winapi.CreateFile`。

原因：DSH 的 Windows 沙箱禁止创建命名管道，MinerU 的 PDF 渲染进程池需要它。

处理：
- 用 `-Tier flash`（纯原生文本解析，无需进程池）；
- 或在工作区外的普通终端执行解析（沙箱不生效）。

### 临时目录权限（`tempfile` / `winerror 5`）

现象：`<tmp>/mineru-api-client-*/output` 创建失败，`Access denied`。

原因：沙箱下 `os.mkdir(path, mode)`（`tempfile.mkdtemp`/`TemporaryDirectory` 使用）会创建出
DACL 不可访问的目录；不带 `mode` 的 `os.mkdir(path)` 正常。

处理：`scripts/sandbox/sitecustomize.py` 去掉 `mode` 参数，`parse.ps1` 通过 `PYTHONPATH`
自动注入，无需手工操作。

### 下载慢 / 卡住

- **PyPI**：用腾讯镜像 `https://mirrors.cloud.tencent.com/pypi/simple`
- **torch CUDA wheel**：`download.pytorch.org` 实测 **0.1 MB/s**（国内），改用 SJTU 镜像
  `https://mirror.sjtu.edu.cn/pytorch-wheels/cu126` 实测 **15–28 MB/s**
- **模型**：`--source modelscope`；HuggingFace 走 Xet 失败时设 `HF_HUB_DISABLE_XET=1`

### uv 认为版本已满足，不替换 wheel

现象：`uv pip install torch==2.12.1 --index-url .../cu126` 报 `Checked 2 packages`，torch 仍是 `+cpu`。

原因：PEP 440 下 `==2.12.1` 会匹配 `2.12.1+cpu`。

处理：加 `--reinstall`，或直接安装本地 wheel 文件。

### LMDeploy / CUDA 版本

`lmdeploy 0.17.0` 的 `_turbomind.cp312-win_amd64.pyd` 链接的是 **CUDA 12** DLL
（`cudart64_12`、`cublas64_12`），因此 Windows 必须装 **cu126** 版 torch（不是 cu128/cu130），
且 `CUDA_PATH` 要指向含这些 DLL 的 `torch\lib`（`cuda_stub` junction）。

### onnxruntime：CPU / GPU / DirectML 三个发行包不能共存

`onnxruntime`、`onnxruntime-gpu`、`onnxruntime-directml` 共用同一个 `onnxruntime/` 包目录，
同时安装会互相覆盖文件（症状：`import onnxruntime` 报 DLL 加载失败，或 CUDA EP 静默消失）。

- MinerU 4.0.12 把 `onnxruntime` 写进了**核心依赖**，基础安装必然带入 CPU 版。
- 本机 Windows 为 `small_backend: torch` + LMDeploy VLM，ONNX 走 CPU EP 即可；
  因此升级时先卸载了旧的 `onnxruntime-gpu 1.30.0`，现行环境是 `onnxruntime 1.31.1` + `onnxruntime-directml 1.24.4`。
- 确需 CUDA / DirectML EP 时，先 `uv pip uninstall onnxruntime onnxruntime-directml` 再装对应发行包，
  不要在保留 CPU 版的情况下直接叠加。

### 显存不足（OOM）

RTX 4060 仅 8GB：
- 降低档位：`-Tier basic`（不需要 VLM）或 `-Tier flash`
- 分批解析，减少单次 `-Paths` 数量
- 长文档会按处理窗口切分（`MINERU_PROCESSING_WINDOW_SIZE`）

### 降级 CPU 模式

4.0 没有 `MINERU_DEVICE_MODE`。改为在配置或环境变量里指定后端：

```powershell
$env:MINERU_MODEL_SMALL_BACKEND = 'onnx'   # CPU 小模型
$env:MINERU_TABLE_DEVICE = 'cpu'           # 表格模型强制 CPU
& "D:\MinerU\mineru-kit.bat" parse <文件> -o <输出.md> --tier basic
```

## 六、性能基准（实测）

| 平台 | 档位 | 用例 | 耗时 |
|---|---|---|---|
| WSL | flash | `sample.docx`（1 页） | 1.7 s |
| WSL | basic | `test.pdf`（1 页，含冷启动） | 9.7 s |
| WSL | standard | `test.pdf`（1 页，VLM，峰值内存约 3.9 GB） | 15.5 s |
| WSL | basic | `Homework9.pdf`（3 页数学） | 产出 3.6 KB / 186 行可读 LaTeX |
| WSL | flash | `Homework9.pdf`（3 页数学） | 产出 573 KB（整页图片 base64，公式不可检索） |

> 结论：**文本型 PDF 用 `basic`，不要用 `flash`**。`flash` 对公式页面会退化成整页图片内联。

## 七、常用命令速查

```bash
# 单文件转 markdown
mineru-kit parse doc.pdf -o doc.md --tier basic

# 指定页范围
mineru-kit parse doc.pdf -o doc.md --tier basic --pages 1-5,8

# 目录批量转换
mineru-kit parse ./docs -o ./out --tier basic

# 需要图片文件时用 zip（含 markdown.md / images/ / middle_json.json）
mineru-kit parse doc.docx -o ./out --tier flash --format zip

# 查看/校验模型
mineru-kit models show
mineru-kit models verify --tier standard
```
