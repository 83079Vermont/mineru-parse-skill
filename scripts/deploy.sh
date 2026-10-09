#!/usr/bin/env bash
# MinerU deployment helper for Linux/WSL: detect / scan hardware / recommend / install
# Bash port of deploy.ps1 — WSL-native install (uv + mineru[torch]==4.0.10 + CUDA torch + llama.cpp VLM).
#
# Usage:
#   Scan only (first-use check):
#     scripts/deploy.sh --scan
#   Install (non-interactive with --yes, preferred for agents):
#     scripts/deploy.sh --install [--mineru-dir ~/MinerU] [--model-dir ~/MinerU/models]
#                         [--backend GPU|CPU|auto] [--yes] [--mirror <pypi-url>|none] [--win-models auto|copy|link|skip]
#
# Exit codes:
#   0  MinerU already deployed / install completed
#   2  MinerU NOT deployed (scan-only mode, ready for install)
#   3  Scan or install failed
#   4  User aborted

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_OUT="$SCRIPT_DIR/mineru.config.linux.json"

MODE="scan"
MinerUDir="${MINERU_HOME:-$HOME/MinerU}"
ModelDir=""
Backend="auto"
AssumeYes=0
Mirror="https://mirrors.cloud.tencent.com/pypi/simple"
WinModels="auto"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scan)         MODE="scan"; shift ;;
        --install)      MODE="install"; shift ;;
        --mineru-dir)   MinerUDir="$2"; shift 2 ;;
        --model-dir)    ModelDir="$2"; shift 2 ;;
        --backend)      Backend="$2"; shift 2 ;;
        --mirror)       Mirror="$2"; shift 2 ;;
        --win-models)   WinModels="$2"; shift 2 ;;
        --yes|-y)       AssumeYes=1; shift ;;
        -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[deploy][warn] unknown arg: $1" >&2; shift ;;
    esac
done

[[ -z "$ModelDir" ]] && ModelDir="$MinerUDir/models"

log()  { echo "[deploy] $*"; }
warn() { echo "[deploy][warn] $*"; }
confirm() { # <prompt> -> 0 yes
    [[ "$AssumeYes" == "1" ]] && return 0
    read -r -p "$1 (y/N) " ans
    [[ "$ans" =~ ^([yY]|[yY][eE][sS])$ ]]
}

json_str() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }

# ---------- detection ----------
find_mineru() {
    local c
    [[ -n "${MINERU_BIN:-}" && -x "${MINERU_BIN:-}" ]] && { echo "$MINERU_BIN"; return; }
    for c in "$SCRIPT_DIR/mineru.config.linux.json" "$HOME/.config/mineru/mineru.config.linux.json"; do
        if [[ -f "$c" ]]; then
            local b; b="$(json_str "$c" mineruBin)"
            [[ -n "$b" && -x "$b" ]] && { echo "$b"; return; }
        fi
    done
    command -v mineru 2>/dev/null && return
    [[ -x "$MinerUDir/mineru.sh" ]] && { echo "$MinerUDir/mineru.sh"; return; }
    echo ""
}

mineru_version() {
    local bin="$1"
    [[ -z "$bin" ]] && { echo ""; return; }
    "$bin" --version 2>&1 | tail -1 || echo ""
}

venv_python_of() { # derive venv python from mineru bin path
    local bin="$1" d
    d="$(dirname "$bin")"
    [[ -x "$d/python" ]] && { echo "$d/python"; return; }     # inside .venv/bin
    [[ -x "$MinerUDir/.venv/bin/python" ]] && { echo "$MinerUDir/.venv/bin/python"; return; }
    echo ""
}

# ---------- hardware scan ----------
detect_gpu() { # sets GPU_NAME GPU_VRAM_MB; returns 0 if nvidia gpu present
    GPU_NAME=""; GPU_VRAM_MB=0
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    local out
    out="$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | head -1)" || true
    [[ -z "$out" ]] && return 1
    GPU_NAME="$(echo "$out" | cut -d, -f1 | sed 's/^ *//;s/ *$//')"
    GPU_VRAM_MB="$(echo "$out" | cut -d, -f2 | tr -dc '0-9')"
    [[ -z "$GPU_VRAM_MB" ]] && GPU_VRAM_MB=0
    return 0
}

is_wsl() { grep -qi 'microsoft' /proc/version 2>/dev/null; }

invoke_scan() {
    log "Scanning MinerU deployment status (Linux/WSL)..."
    local bin
    bin="$(find_mineru)"
    if [[ -n "$bin" ]]; then
        log "[ok] MinerU detected: $bin"
        local v; v="$(mineru_version "$bin")"
        [[ -n "$v" ]] && log "version: $v"
        echo "DONE_MinerU_PRESENT"
        return 0
    fi

    log "MinerU NOT deployed. Scanning hardware..."
    local has_gpu=0
    if detect_gpu; then
        has_gpu=1
        echo "--- GPU ---"
        echo "  $GPU_NAME | VRAM $(( GPU_VRAM_MB / 1024 ))GB"
    else
        echo "--- GPU ---"
        echo "  none (nvidia-smi unavailable -> CPU mode)"
    fi
    is_wsl && echo "  (WSL2 detected: GPU via WSL CUDA driver is supported)"

    echo "--- CPU ---"
    echo "  $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//') | $(nproc) cores"
    echo "--- RAM ---"
    echo "  $(free -g | awk '/^Mem:/{print $2}') GB total"
    echo "--- DISK ---"
    echo "  $HOME free: $(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9') GB (install here)"
    [[ -d /mnt/d ]] && echo "  /mnt/d free: $(df -BG --output=avail /mnt/d 2>/dev/null | tail -1 | tr -dc '0-9') GB (Windows D:)"

    echo "--- PYTHON ---"
    local found_py=0
    for t in uv python3 python conda pip3; do
        if command -v "$t" >/dev/null 2>&1; then
            found_py=1
            echo "  $t: $("$t" --version 2>&1 | head -1) @ $(command -v "$t")"
        fi
    done
    [[ "$found_py" == "0" ]] && warn "No Python/uv found. Install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"

    echo "--- WINDOWS MODELS ---"
    local win_models
    win_models="$(ls -d /mnt/*/MinerU/models 2>/dev/null | head -1)"
    [[ -n "$win_models" ]] && echo "  found: $win_models ($(du -sh "$win_models" 2>/dev/null | cut -f1))"
    echo "  note: MinerU 4.0 uses new bundles (MinerU-4_models_torch/_onnx + a GGUF VLM);"
    echo "        3.x Windows model dirs are NOT reusable -> models download via modelscope."

    echo "--- RECOMMENDATION ---"
    if [[ "$has_gpu" == "1" && "$GPU_VRAM_MB" -ge 6144 ]]; then
        echo "  => GPU install: mineru[torch]==4.0.10 + CUDA torch (Linux PyPI wheel) + llama.cpp VLM | disk ~10GB"
    elif [[ "$has_gpu" == "1" ]]; then
        echo "  => GPU install (low VRAM): mineru[torch], prefer -Tier basic | disk ~8GB"
    else
        echo "  => CPU install: mineru[torch] or base, prefer -Tier flash/basic | disk ~6GB"
    fi
    echo "  install cmd: $SCRIPT_DIR/deploy.sh --install --yes"
    echo "DONE_MinerU_ABSENT"
    return 2
}

# ---------- install ----------
invoke_install() {
    local bin; bin="$(find_mineru)"
    if [[ -n "$bin" ]]; then
        log "MinerU already deployed at $bin, nothing to install."
        return 0
    fi

    if ! command -v uv >/dev/null 2>&1; then
        warn "uv not found; falling back to python3 -m venv + pip (slower)."
    fi

    local pyver=""
    if command -v uv >/dev/null 2>&1; then
        pyver="3.12"
    else
        pyver="$(python3 --version 2>/dev/null | grep -oE '3\.(1[0-2])' | head -1)"
        [[ -z "$pyver" ]] && { warn "Need Python 3.10-3.12 or uv. Aborting."; return 3; }
    fi

    if ! confirm "Use install dir '$MinerUDir'?"; then read -r -p "Enter MinerU install directory: " x; [[ -n "$x" ]] && MinerUDir="$x"; ModelDir="$MinerUDir/models"; fi
    if ! confirm "Use model dir '$ModelDir'?"; then read -r -p "Enter model directory: " x; [[ -n "$x" ]] && ModelDir="$x"; fi

    detect_gpu || true
    if [[ "$Backend" == "auto" ]]; then
        if [[ "${GPU_VRAM_MB:-0}" -ge 6144 ]]; then Backend="GPU"; elif [[ "${GPU_VRAM_MB:-0}" -gt 0 ]]; then Backend="GPU"; else Backend="CPU"; fi
    fi
    if ! confirm "Install with backend '$Backend'?"; then read -r -p "Enter backend (GPU/CPU): " x; [[ "$x" == "GPU" || "$x" == "CPU" ]] && Backend="$x"; fi

    log "Install plan: dir=$MinerUDir | models=$ModelDir | backend=$Backend | mirror=$Mirror"
    if ! confirm "Proceed with install?"; then echo "USER_ABORTED"; return 4; fi

    mkdir -p "$MinerUDir" "$ModelDir"
    local venv="$MinerUDir/.venv"
    local venvPy="$venv/bin/python"

    # 1. venv
    log "Creating virtualenv (python $pyver)..."
    if command -v uv >/dev/null 2>&1; then
        uv venv --python "$pyver" "$venv" || { warn "uv venv failed"; return 3; }
    else
        python3 -m venv "$venv" || { warn "venv creation failed"; return 3; }
        "$venvPy" -m pip install --upgrade pip || true
    fi

    local uvpip=()
    if command -v uv >/dev/null 2>&1; then
        uvpip=(uv pip install --python "$venvPy")
        [[ -n "$Mirror" && "$Mirror" != "none" ]] && uvpip+=(--default-index "$Mirror")
    else
        uvpip=("$venvPy" -m pip install)
        [[ -n "$Mirror" && "$Mirror" != "none" ]] && uvpip+=(-i "$Mirror" --trusted-host "$(echo "$Mirror" | sed 's|https\?://\([^/]*\).*|\1|')")
    fi

    # 2. mineru 4.0 (Linux: torch small models; the VLM runs via llama.cpp from the base package)
    log "Installing mineru[torch]==4.0.10 (this may take several minutes)..."
    "${uvpip[@]}" 'mineru[torch]==4.0.10' || { warn "mineru install failed. Check network/mirror, then rerun."; return 3; }

    # 3. torch cuda verify
    if [[ "$Backend" == "GPU" ]]; then
        log "Verifying torch CUDA..."
        local cuda_ok
        cuda_ok="$("$venvPy" -c "import torch; print('yes' if torch.cuda.is_available() else 'no')" 2>/dev/null)" || cuda_ok="no"
        if [[ "$cuda_ok" != "yes" ]]; then
            warn "torch CUDA unavailable; reinstalling CUDA torch from PyPI default wheel..."
            "${uvpip[@]}" --torch-backend=cu126 torch torchvision || { warn "CUDA torch install failed; parse will run CPU."; }
            cuda_ok="$("$venvPy" -c "import torch; print('yes' if torch.cuda.is_available() else 'no')" 2>/dev/null)" || cuda_ok="no"
            [[ "$cuda_ok" == "yes" ]] && log "[ok] torch CUDA working" || warn "torch CUDA still unavailable (driver issue?)."
        else
            log "[ok] torch CUDA working: $("$venvPy" -c "import torch; print(torch.__version__)" 2>/dev/null)"
        fi
    fi

    # 4. config.yaml (4.0 reads $MINERU_HOME/config.yaml; the 3.x mineru.json is no longer read)
    log "Writing config.yaml..."
    mkdir -p "$ModelDir"
    local engine="llama-cpp"
    cat > "$MinerUDir/config.yaml" <<EOF
model:
  source: modelscope
  base_dir: $ModelDir
  small_backend: torch
  vlm:
    engine: $engine
EOF
    export MINERU_HOME="$MinerUDir"
    export MINERU_CONFIG="$MinerUDir/config.yaml"

    # 5. models for the standard tier.
    # NOTE: 4.0 uses new bundles (MinerU-4_models_torch/_onnx + a GGUF VLM), so the 3.x
    # Windows `models/` (Layout/MFR/OCR/TabCls/TabRec) and `vlm-model/` are NOT reusable;
    # `--win-models` is accepted but has no effect on 4.0.
    log "Downloading models for tier standard via modelscope..."
    "$venv/bin/mineru-kit" models download --tier standard --source modelscope \
        || { warn "model download failed. Check network, then rerun."; return 3; }
    "$venv/bin/mineru-kit" models verify --tier standard \
        || warn "model verify reported missing resources (parsing may still work for lower tiers)"

    # 6. wrappers: mineru.sh (document library) + mineru-kit.sh (stateless parsing)
    log "Writing mineru.sh / mineru-kit.sh wrappers..."
    local exe wrapper
    for pair in "mineru:mineru.sh" "mineru-kit:mineru-kit.sh"; do
        exe="${pair%%:*}"; wrapper="${pair##*:}"
        cat > "$MinerUDir/$wrapper" <<EOF
#!/usr/bin/env bash
export MINERU_HOME="$MinerUDir"
export MINERU_CONFIG="$MinerUDir/config.yaml"
export MINERU_MODEL_SOURCE=local
export MINERU_MODEL_SMALL_BACKEND=torch
export MINERU_MODEL_VLM_ENGINE=$engine
exec "$venv/bin/$exe" "\$@"
EOF
        chmod +x "$MinerUDir/$wrapper"
    done

    # 7. skill config
    log "Writing mineru.config.linux.json for parse.sh..."
    cat > "$CONFIG_OUT" <<EOF
{
  "mineruBin": "$MinerUDir/mineru.sh",
  "mineruKitBin": "$MinerUDir/mineru-kit.sh",
  "venvPython": "$venvPy",
  "modelsDir": "$ModelDir",
  "mineruHome": "$MinerUDir"
}
EOF

    echo "[deploy][ok] Install complete at $MinerUDir"
    echo "[deploy] Verify:  $SCRIPT_DIR/parse.sh -Paths <small.pdf>"
    echo "DONE_MinerU_INSTALLED"
    return 0
}

# ---------- main ----------
if [[ "$MODE" == "install" ]]; then
    invoke_install; exit $?
else
    invoke_scan; exit $?
fi
