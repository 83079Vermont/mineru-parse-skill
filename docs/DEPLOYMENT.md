# MinerU 部署环境与故障排查

本文档记录 MinerU 的部署流程与故障排查方法。日常解析只需调用 `scripts/parse.ps1`；`scripts/deploy.ps1` 负责首次检测与半自动部署。

## deploy.ps1 使用

**检测（首次使用必跑）**：

```powershell
& scripts\deploy.ps1 -Scan
```

- `DONE_MinerU_PRESENT`：本机已部署，输出 MinerU 路径与版本
- `DONE_MinerU_ABSENT`：未部署，输出硬件扫描（GPU/VRAM/CPU/内存/磁盘/Python）与推荐方案

**半自动安装**：

```powershell
& scripts\deploy.ps1 -Install [-MinerUDir <安装目录>] [-ModelDir <模型目录>] [-Backend GPU|CPU|auto]
```

- 各参数缺省时交互询问；用户可自定义安装目录与模型下载目录
- 流程：创建 venv → pip 安装 mineru → 安装 torch（GPU 试 cu124 / CPU 直装）→ onnxruntime-gpu（可选）→ modelscope 下载模型 → 生成 `mineru.json`、`mineru.bat`、`mineru.config.json`
- GPU torch 国内网络失败时会提示按下方「手动安装」步骤处理，不阻塞后续指引
- 安装完成后可用 `parse.ps1 -Paths <小PDF>` 冒烟验证

**MinerU 定位链**（`parse.ps1` 与 `deploy.ps1` 共用）：环境变量 `MINERU_BAT` → 脚本同级 `mineru.config.json` → 用户目录 `.config\mineru\mineru.config.json` → 默认 `D:\MinerU\mineru.bat` → PATH 中 `mineru`。

## 部署环境（2026-08 已升级 GPU）

- 安装位置：`D:\MinerU`
- 虚拟环境：`D:\MinerU\.venv`，Python 3.12，MinerU 3.4.4
- 启动脚本：`D:\MinerU\mineru.bat`，封装了环境变量：
  - `MINERU_TOOLS_CONFIG_JSON=D:\MinerU\mineru.json`
  - `MINERU_MODEL_SOURCE=modelscope`
  - `MINERU_DEVICE_MODE=cuda`
  - `CUDA_PATH=D:\MinerU\cuda_stub`（junction 指向 `torch\lib`）
- GPU：RTX 4060 8GB，CUDA 后端可用

### 组件安装记录

- torch 2.5.1+cu124 + torchvision 0.20.1+cu124：从 Anaconda 官方 conda 通道（经 SJTU 镜像）下载 `.tar.bz2` 手动解压到 `Lib\site-packages`（国内 pip wheel 镜像已停更，download.pytorch.org 被 403 封锁）
- CUDA 运行时：pip 安装 `nvidia-cuda-runtime/cublas/cufft/curand/cusolver/cusparse/npp/nvjpeg/nvjitlink/nvrtc-cu12`（腾讯 pypi 镜像），DLL 复制进 `torch\lib`；mkl 2023.1 + intel-openmp + libuv（conda main 通道解压复制）
- onnxruntime-gpu 1.28.0（CUDAExecutionProvider 可用）
- `D:\MinerU\cuda_stub\bin` 为 junction → `torch\lib`（lmdeploy turbomind 需要 CUDA_PATH 存在）
- 模型源：modelscope（mineru.json 配置 `D:\MinerU\models`）

## 后端与性能基准

| 后端 | 说明 | 60 页基准 |
|---|---|---|
| hybrid-engine | 默认，最快且精度最高 | 83s |
| pipeline + GPU | 通用 | 88s |
| pipeline CPU | 慢 | 157s |

`parse.ps1` 的 `-Backend auto` 按页数选择：< 10 页用 pipeline（快），否则 hybrid-engine（精度高）。

## 故障排查

### 显存不足（OOM）
RTX 4060 只有 8GB，解析超长文档或大批量图片可能 OOM。缓解：
- 缩小单次 `-Paths` 输入数量，分批解析
- 对 hybrid 使用 `-Effort medium`（默认，禁用图表分析省显存）
- 换 pipeline 后端

### CUDA 初始化失败 / 找不到 DLL
检查：
- `D:\MinerU\cuda_stub` junction 是否完好（`fsutil reparsepoint query`）
- `torch\lib` 下 CUDA DLL 是否存在
- 日志出现 `onnxruntime ... TryGetProviderInfo_CUDA` 时通常已自动回退 CPU，功能仍可用

### 降级 CPU 模式
临时改环境变量后直接调用 exe（不要用 bat，否则会被覆盖回 cuda）：

```powershell
$env:MINERU_DEVICE_MODE = "cpu"
& "D:\MinerU\.venv\Scripts\mineru.exe" -p <文件> -o <输出目录> -b pipeline
```

### 模型下载失败
模型源为 modelscope（`D:\MinerU\models`）。若下载失败，检查网络与磁盘剩余空间；模型已下载过则无需重复下载。

### 进程残留 / 端口占用
MinerU CLI 每次启动临时本地服务（随机端口），结束后自动关闭。若出现残留进程，可在任务管理器结束 `mineru.exe` / `python.exe` 相关进程。

### 清理失败
`parse.ps1` 删除辅助文件失败（如被占用）时跳过并继续，可在解析完成后手动清理源目录中的 `_middle.json`、`images/` 等残留。
