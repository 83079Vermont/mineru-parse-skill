# MinerU 部署环境、迁移与故障排查

本技能面向 **MinerU 4.1**（`mineru-kit` CLI）。日常解析只需调用 `scripts/parse.ps1`（Windows）或
`scripts/parse.sh`（Linux/WSL）；对应的 `deploy` 脚本负责首次检测与半自动部署。

## 一、4.x 与 3.x 的关键差异

| 维度 | 3.x | 4.x |
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
| Python 版本 | 3.10+ | **3.11–3.14**（4.1 起 3.10 掉出支持） |
| 模型 | pipeline 小模型目录 + MinerU2.5-Pro safetensors | `MinerU-4_models_torch`/`_onnx` 包 + GGUF/LMDeploy VLM |
| 模型下载 | `python -m mineru.cli.models_download -s modelscope -m all` | `mineru-kit models download --tier standard --source modelscope` |
| markdown 产物 | `<out>/<stem>/<method>/<stem>.md` + `images/` | 单个自包含 `.md`（图片内联 base64）；`--format zip` 才有 `images/` |
| HTTP API | `/file_parse`、`/tasks` | V1：`/v1/tasks`（4.1）；4.0 为 `/v1/uploads` + `/v1/parse/jobs` |

### 4.0 → 4.1 的关键变化（4.1.3 实测）

| 维度 | 4.0.12 | 4.1.3 |
|---|---|---|
| `mineru-kit parse` | — | **完全不变**（`parse --help` 与 4.0.12 逐字一致，产物语义也一致） |
| 新增子命令 | — | `hardware detect` / `hardware info`（硬件自检 + 推荐档位）、`file-parse-server`（同步单文件服务，默认 8003） |
| `api-server` / `webui` | `--tier` 可空、`--no-flash` / `--no-advanced` / `--allow-local-source` / `--max-inline-bytes`；webui `--api-server-tier` | `--tier` 默认 `auto`（含自身即上限），上述 4 个选项与 `--api-server-tier` **移除** |
| config.yaml | 无 ONNX 设备键 | 新增 `model.onnx_device: auto\|cpu\|gpu`；配套 `MINERU_MODEL_ONNX_DEVICE`、`MINERU_INTRA_OP_NUM_THREADS`、`MINERU_INTER_OP_NUM_THREADS` |
| 依赖 | `onnxruntime` 必需 | `onnx` 进基础依赖；Windows x64 为 `onnxruntime-directml`，Linux x86_64 另加 `onnxruntime-ep-webgpu`；`docvortex 0.6.9`、`lmdeploy 0.18`、`mineru-vl-utils 2.0.8`、`mineru-llama-cpp 0.2.0` |
| 产物 | zip 内含 `model_output.json` | `model_output.json` **不再写入产物**（ModelJson 仅内部使用） |
| HTTP | `/v1/uploads` + `/v1/parse/jobs` | `/v1/tasks`；错误体 `code/message`；恢复目录 `tasks-v4-` → `tasks-v5-`（旧目录不加载、不迁移） |
| 模型集合 | `MinerU-4_models_torch` / `_onnx` | 不变，**升级不需要重新下载模型** |

## 二、当前部署环境

两侧当前均为 **4.1.3**（2026-10-31 由 4.0.12 升级）；3.x 与 4.0.10 环境都以改名方式保留，可随时回滚。

### Windows

- 安装位置：`D:\MinerU`
- 虚拟环境：`D:\MinerU\.venv`（Python 3.12.10）
- MinerU：`4.1.3`（`mineru[full]`），`lmdeploy 0.18.0`，`docvortex 0.6.9`
- torch：`2.12.1+cu126`（CUDA 12.6；Windows VLM 仍走 LMDeploy 0.18 + CUDA 12，升级时 torch 保持不动）
- 配置：`D:\MinerU\config.yaml`
- 包装脚本：`mineru.bat`（文档库）、**`mineru-kit.bat`（解析，技能使用）**
- 模型：`D:\MinerU\models\v4`
- `D:\MinerU\cuda_stub`：junction → `.venv\Lib\site-packages\torch\lib`（LMDeploy turbomind 需要 `CUDA_PATH` 存在）
- GPU：RTX 4060 Laptop 8GB，驱动 617.14

### WSL（Ubuntu-26.10，用户 wsl1）

- 安装位置：`/home/wsl1/MinerU`
- 虚拟环境：`/home/wsl1/MinerU/.venv`（Python 3.12.14，uv 管理）
- MinerU：`4.1.3`（`mineru[torch]`），`docvortex 0.6.9`，VLM 引擎 **llama.cpp**（`mineru-llama-cpp 0.2.0`）
- torch：`2.15.0+cu132`（4.1.3 升级时 uv 顺带升级，仍满足 `torch<3`；`torch.cuda.is_available()=True`）
- 配置：`/home/wsl1/MinerU/config.yaml`
- 包装脚本：`mineru.sh`（文档库）、**`mineru-kit.sh`（解析）**
- 模型：`/home/wsl1/MinerU/models`（`MinerU-4_models_torch` + `MinerU2.5-Pro-2605-1.2B-GGUF`，共约 2.0 GB）
- GPU 直通：`/dev/dxg` + nvidia-smi 可见 RTX 4060

### 4.0.12 → 4.1.3 升级记录（2026-10-31）

| 平台 | 升级命令（国内源） | 结果 |
|---|---|---|
| Windows | `uv pip install --python D:\MinerU\.venv\Scripts\python.exe --upgrade "mineru[full]==4.1.3" --index-url https://mirrors.cloud.tencent.com/pypi/simple --extra-index-url https://mirror.sjtu.edu.cn/pytorch-wheels/cu126` | 解析 167 包，装 49 / 卸 44，约 50 s |
| WSL | `uv pip install --python ~/MinerU/.venv/bin/python --upgrade "mineru[torch]==4.1.3" --default-index https://mirrors.cloud.tencent.com/pypi/simple` | 变更包相近，完成后再 `uv pip check` 全绿 |

- 关键依赖变化：`mineru 4.0.12 → 4.1.3`、`docvortex 0.6.5 → 0.6.9`、`lmdeploy 0.17.0 → 0.18.0`（仅 Windows [full]）、
  `mineru-vl-utils 2.0.5 → 2.0.8`、`mineru-llama-cpp 0.1.2 → 0.2.0`、`transformers 5.19.0 → 5.22.1`、
  新增 `onnx 1.23.2`、`ml-dtypes`、`truststore`、`httpcore2`/`httpx2`。
- torch：Windows 保持 `2.12.1+cu126`（LMDeploy 0.18 的 turbomind 仍链 CUDA 12）；
  WSL 被 uv 顺带升到 `2.15.0+cu132`，`torch.cuda.is_available()=True`。
- 模型权重无变更：`models verify --tier standard` 两侧全绿，**不需要重新下载**。
- 校验：`uv pip check` Windows 170 包 / WSL 149 包全部兼容；`mineru-kit parse --help` 与 4.0.12 逐字一致；
  `basic` 与 `standard`（VLM）两侧均正常出产物；技能 `parse.ps1` 的 markdown / zip 两种格式均通过。
- 备份：升级前的环境与依赖清单见 `requirements-4.0.12.lock`，升级后为 `requirements-4.1.3.lock`。
- 已知非致命告警：Windows + LMDeploy 在 8 GB 卡上首次 warm-up 打印
  `[TM][ERROR] Warm-up for 8320 tokens failed with status 6`，随后照常解析并产出，见下方「LMDeploy warm-up 告警」。

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
| Windows | `D:\MinerU\.venv-4.0.10.bak`（回 4.0.10）<br>`D:\MinerU\.venv-3.4.5.bak`（回 3.4.5） | `requirements-4.0.10.lock` / `requirements-4.0.12.lock` / `requirements-4.1.3.lock` | `D:\MinerU\_backup-3.4.5\{mineru.json,mineru.bat,pip-freeze-3.4.5.txt,...}` |
| WSL | `~/MinerU/.venv-4.0.10.bak`<br>`~/MinerU/.venv-3.4.5.bak` | 同上（`requirements-4.1.3.lock` 含 torch） | `~/MinerU/_backup-3.4.5/{mineru.json,mineru.sh,pip-freeze-3.4.5.txt,...}` |

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

## 三、3.x → 4.x 配置映射

| 3.x | 4.x | 说明 |
|---|---|---|
| `models-dir.pipeline` | `model.base_dir` | 指向新的 4.x 模型根 |
| `models-dir.vlm` | `model.vlm.engine` | 3.x 的 VLM 目录不再使用，改由引擎从 4.x 仓库取权重 |
| `model-source: local` | `model.source: local` | 运行时离线；下载时临时用 `--source modelscope` |
| `MINERU_TOOLS_CONFIG_JSON` | `MINERU_HOME` + `MINERU_CONFIG` | 4.x 读 config.yaml |
| `MINERU_DEVICE_MODE=cuda` | —— | 移除；GPU 由 `small_backend: torch` + VLM 引擎体现 |
| `CUDA_PATH=<cuda_stub>` | 保留（仅 GPU + LMDeploy） | turbomind 通过它找 CUDA DLL |
| `latex-delimiter-config` | 未迁移 | 4.x config.yaml 无对应字段；数学定界符由渲染器决定 |
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

4.1 流程：`uv venv`（Python 3.11–3.14，推荐 3.12）→ `mineru[full]==4.1.3`（Linux 用 `mineru[torch]`）→
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

`lmdeploy 0.18.0`（4.1.3 装的是这个版本）的 `_turbomind.cp312-win_amd64.pyd` 仍然链接 **CUDA 12** DLL
（`cudart64_12`、`cublas64_12`），因此 Windows 必须装 **cu126** 版 torch（不是 cu128/cu130），
且 `CUDA_PATH` 要指向含这些 DLL 的 `torch\lib`（`cuda_stub` junction）。

### LMDeploy warm-up 告警（非致命）

现象：

```
[TM][ERROR][...][turbomind.cc:486] Warm-up for 8320 tokens failed with status 6
```

原因：8 GB 显存不足以容纳默认的 8320-token warm-up 配置，LMDeploy 放弃该预热档位。

处理：**无需处理**——4.1.3 实测随后仍用 lmdeploy 引擎正常解析并产出（退出码 0）。
只有真的报 OOM 或 `no_engine` 时才降档到 `-Tier basic`。

### onnxruntime：CPU / GPU / DirectML 三个发行包不能共存

`onnxruntime`、`onnxruntime-gpu`、`onnxruntime-directml` 共用同一个 `onnxruntime/` 包目录，
同时安装会互相覆盖文件（症状：`import onnxruntime` 报 DLL 加载失败，或 CUDA EP 静默消失）。

- MinerU 4.1 在 Windows x64 上把 `onnxruntime-directml` 写成默认依赖（Linux x86_64 为 `onnxruntime` + `onnxruntime-ep-webgpu`），
  并且 `onnx` 也进了基础依赖；4.0.12 当年是把 CPU 版 `onnxruntime` 作为核心依赖带进来的。
- 本机 Windows 为 `small_backend: torch` + LMDeploy VLM，ONNX 走 CPU EP 即可；
  因此升级时先卸载了旧的 `onnxruntime-gpu 1.30.0`，现行环境是 `onnxruntime 1.31.1` + `onnxruntime-directml 1.24.4`。
- 4.1 新增 `model.onnx_device: auto|cpu|gpu`，需要指定 ONNX 设备时优先用它，而不是换发行包。
- 确需 CUDA / DirectML EP 时，先 `uv pip uninstall onnxruntime onnxruntime-directml` 再装对应发行包，
  不要在保留 CPU 版的情况下直接叠加。

### 显存不足（OOM）

RTX 4060 仅 8GB：
- 降低档位：`-Tier basic`（不需要 VLM）或 `-Tier flash`
- 分批解析，减少单次 `-Paths` 数量
- 长文档会按处理窗口切分（`MINERU_PROCESSING_WINDOW_SIZE`）

### 降级 CPU 模式

4.x 没有 `MINERU_DEVICE_MODE`。改为在配置或环境变量里指定后端：

```powershell
$env:MINERU_MODEL_SMALL_BACKEND = 'onnx'   # CPU 小模型
$env:MINERU_MODEL_ONNX_DEVICE = 'cpu'      # 4.1 新增：ONNX 设备 auto|cpu|gpu
$env:MINERU_INTRA_OP_NUM_THREADS = '8'     # 4.1 新增：限制 ONNX 线程
$env:MINERU_TABLE_DEVICE = 'cpu'           # 表格模型强制 CPU
& "D:\MinerU\mineru-kit.bat" parse <文件> -o <输出.md> --tier basic
```

## 六、性能基准（实测）

| 平台 | 档位 | 用例 | 耗时 |
|---|---|---|---|
| Windows | basic | 2 页讲义 PDF（4.1.3，含模型加载） | 36 s |
| Windows | standard | 同上（4.1.3，VLM） | 33 s |
| WSL | basic | `test.pdf`（1 页，4.1.3，含冷启动） | 14.5 s |
| WSL | standard | `test.pdf`（1 页，4.1.3，VLM/llama.cpp） | 27.3 s |
| WSL | flash | `sample.docx`（1 页，4.0.12） | 1.7 s |
| WSL | basic | `test.pdf`（1 页，4.0.12，含冷启动） | 9.7 s |
| WSL | standard | `test.pdf`（1 页，4.0.12，VLM，峰值内存约 3.9 GB） | 15.5 s |
| WSL | basic | `Homework9.pdf`（3 页数学，4.0.12） | 产出 3.6 KB / 186 行可读 LaTeX |
| WSL | flash | `Homework9.pdf`（3 页数学，4.0.12） | 产出 573 KB（整页图片 base64，公式不可检索） |

> 结论：**文本型 PDF 用 `basic`，不要用 `flash`**。`flash` 对公式页面会退化成整页图片内联。

## 七、常用命令速查

```bash
# 硬件自检（4.1 新增）：推荐档位上限 / 系统与运行时详情
mineru-kit hardware detect
mineru-kit hardware info

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
