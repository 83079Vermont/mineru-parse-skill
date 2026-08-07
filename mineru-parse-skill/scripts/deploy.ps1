# MinerU deployment helper: detect / scan hardware / recommend / semi-automatic install
#
# Usage:
#   Scan only (first-use check):
#     & scripts\deploy.ps1 -Scan
#   Semi-automatic install (interactive confirmations):
#     & scripts\deploy.ps1 -Install [-MinerUDir <path>] [-ModelDir <path>] [-Backend GPU|CPU|auto]
#
# Exit codes:
#   0  MinerU already deployed / install completed
#   2  MinerU NOT deployed (scan-only mode, ready for install)
#   3  Scan or install failed
#   4  User aborted

param(
    [switch]$Scan,
    [switch]$Install,
    [string]$MinerUDir = '',
    [string]$ModelDir = '',
    [ValidateSet('GPU', 'CPU', 'auto')]
    [string]$Backend = 'auto'
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step([string]$msg) { Write-Host "[deploy] $msg" }
function Write-Warn([string]$msg) { Write-Host "[deploy][warn] $msg" }
function Confirm-Yes([string]$prompt) {
    $ans = Read-Host "$prompt (y/N)"
    return ($ans -match '^(y|yes)$')
}

# ---------- MinerU detection ----------
function Find-MinerU {
    $candidates = @()
    if ($env:MINERU_BAT) { $candidates += $env:MINERU_BAT }
    if (Test-Path 'D:\MinerU\mineru.bat') { $candidates += 'D:\MinerU\mineru.bat' }
    $cmd = Get-Command mineru -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Get-MineruVersion([string]$bat) {
    if (-not $bat) { return '' }
    $dir = Split-Path -Parent $bat
    $exe = Join-Path $dir '.venv\Scripts\mineru.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $dir 'mineru.exe' }
    if (Test-Path -LiteralPath $exe) {
        try {
            $ver = & $exe --version 2>&1
            return ($ver -join ' ').Trim()
        } catch { return '' }
    }
    return ''
}

# ---------- Hardware scan ----------
function Get-GpuInfo {
    $nvsmiLines = @()
    $nvsmiCmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvsmiCmd) {
        try {
            $nvsmiLines = @(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1)
        } catch { }
    }
    $gpus = @()
    try {
        $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        $nvIndex = 0
        foreach ($vc in $vcs) {
            $isNv = ($vc.Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX')
            $vramMb = 0
            if ($isNv -and $nvsmiLines.Count -gt $nvIndex) {
                $parts = ($nvsmiLines[$nvIndex] -split ',')
                if ($parts.Count -ge 2) {
                    $mem = $parts[1] -replace '[^\d]', ''
                    [double]::TryParse($mem, [ref]$vramMb) | Out-Null
                }
            }
            if ($isNv) { $nvIndex++ }
            if ($vramMb -le 0 -and $vc.AdapterRAM -gt 0) {
                $vramMb = [math]::Round($vc.AdapterRAM / 1MB, 0)
            }
            $gpus += [pscustomobject]@{
                Name       = $vc.Name
                VramMb     = [int]$vramMb
                Driver     = $vc.DriverVersion
                HasNvidia  = $isNv
            }
        }
    } catch { }
    return $gpus
}

function Get-CpuInfo {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        return [pscustomobject]@{ Name = $cpu.Name; Cores = $cpu.NumberOfCores }
    } catch { return [pscustomobject]@{ Name = 'unknown'; Cores = 0 } }
}

function Get-RamInfo {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        return [pscustomobject]@{ TotalGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
    } catch { return [pscustomobject]@{ TotalGb = 0 } }
}

function Get-DiskFree([string]$path) {
    try {
        $root = [IO.Path]::GetPathRoot($path)
        $device = $root.TrimEnd('\')
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$device'" -ErrorAction SilentlyContinue
        if ($d) { return [math]::Round($d.FreeSpace / 1GB, 1) }
    } catch { }
    return -1
}

function Get-PythonInfo {
    $found = @()
    $cands = @(
        @{ Label = 'python'; Cmd = 'python' },
        @{ Label = 'py launcher'; Cmd = 'py' },
        @{ Label = 'conda'; Cmd = 'conda' },
        @{ Label = 'uv'; Cmd = 'uv' }
    )
    foreach ($c in $cands) {
        $cmd = Get-Command $c.Cmd -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $ver = & $c.Cmd --version 2>&1
                $found += [pscustomobject]@{ Tool = $c.Label; Path = $cmd.Source; Version = ($ver -join ' ').Trim() }
            } catch {
                $found += [pscustomobject]@{ Tool = $c.Label; Path = $cmd.Source; Version = 'found' }
            }
        }
    }
    return $found
}

function Get-NvidiaSmi {
    $nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $nvsmi) { return $null }
    try {
        $out = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1
        if ($out) { return ($out -join ' | ') }
    } catch { }
    return $null
}

function Invoke-Scan {
    Write-Step 'Scanning MinerU deployment status...'
    $bat = Find-MinerU
    if ($bat) {
        $ver = Get-MineruVersion $bat
        Write-Host "[deploy][ok] MinerU detected: $bat"
        if ($ver) { Write-Host "[deploy] version: $ver" }
        Write-Host 'DONE_MinerU_PRESENT'
        return 0
    }

    Write-Step 'MinerU NOT deployed. Scanning hardware...'
    Write-Host '--- GPU ---'
    $gpus = Get-GpuInfo
    if ($gpus.Count -eq 0) {
        Write-Host '  (none / generic display adapter)'
    } else {
        foreach ($g in $gpus) {
            $vram = if ($g.VramMb -gt 0) { ("{0} GB" -f [math]::Round($g.VramMb / 1024, 1)) } else { 'unknown' }
            Write-Host ("  {0} | VRAM {1} | driver {2} | nvidia={3}" -f $g.Name, $vram, $g.Driver, $g.HasNvidia)
        }
    }
    $nvsmi = Get-NvidiaSmi
    if ($nvsmi) { Write-Host "  nvidia-smi: $nvsmi" }

    $cpu = Get-CpuInfo
    Write-Host "--- CPU ---"
    Write-Host "  $($cpu.Name) | cores $($cpu.Cores)"

    $ram = Get-RamInfo
    Write-Host "--- RAM ---"
    Write-Host "  $($ram.TotalGb) GB"

    Write-Host "--- DISK ---"
    $diskPaths = @('D:\', $env:USERPROFILE)
    foreach ($p in $diskPaths) {
        $free = Get-DiskFree $p
        if ($free -ge 0) { Write-Host "  $p free: $free GB" }
    }

    Write-Host "--- PYTHON ---"
    $pys = Get-PythonInfo
    if ($pys.Count -eq 0) {
        Write-Host '  none found'
    } else {
        foreach ($p in $pys) { Write-Host ("  {0}: {1} @ {2}" -f $p.Tool, $p.Version, $p.Path) }
    }

    Write-Host '--- RECOMMENDATION ---'
    $hasNvidiaGpu = $false
    $bestVramGb = 0
    foreach ($g in $gpus) {
        if ($g.HasNvidia) {
            $hasNvidiaGpu = $true
            $gb = [math]::Round($g.VramMb / 1024, 1)
            if ($gb -gt $bestVramGb) { $bestVramGb = $gb }
        }
    }
    if ($hasNvidiaGpu -and $bestVramGb -ge 6) {
        Write-Host "  => GPU full install (torch cu124 + hybrid-engine) | disk ~8GB | est. download ~5GB"
    }
    elseif ($hasNvidiaGpu) {
        Write-Host "  => GPU install (torch cu124) + prefer pipeline backend on 8GB VRAM limit | disk ~8GB"
    }
    else {
        Write-Host "  => CPU install (torch CPU + pipeline backend) | disk ~6GB"
    }
    if ($pys.Count -eq 0) {
        Write-Warn 'No Python found. Install Python 3.10+ first (winget install Python.Python.3.12 or python.org).'
    }
    Write-Host 'DONE_MinerU_ABSENT'
    return 2
}

# ---------- Install ----------
function Invoke-Install {
    $bat = Find-MinerU
    if ($bat) {
        Write-Step "MinerU already deployed at $bat, nothing to install."
        return 0
    }

    $python = $null
    foreach ($p in (Get-PythonInfo)) {
        if ($p.Tool -eq 'python' -or $p.Tool -eq 'py launcher') { $python = $p; break }
    }
    if (-not $python) {
        Write-Warn 'No Python found. Install Python 3.10+ first, then rerun.'
        return 3
    }

    # Resolve install dir
    if (-not $MinerUDir) {
        $MinerUDir = 'D:\MinerU'
        if (-not (Confirm-Yes "Use install dir '$MinerUDir'?")) {
            $input = Read-Host 'Enter MinerU install directory'
            if ($input) { $MinerUDir = $input }
        }
    }
    # Resolve model dir
    if (-not $ModelDir) {
        $ModelDir = Join-Path $MinerUDir 'models'
    }
    if (-not (Confirm-Yes "Model download dir '$ModelDir'?")) {
        $input = Read-Host 'Enter model directory'
        if ($input) { $ModelDir = $input }
    }
    # Resolve backend
    $gpus = Get-GpuInfo
    $hasNvidiaGpu = @($gpus | Where-Object { $_.HasNvidia }).Count -gt 0
    if ($Backend -eq 'auto') {
        $Backend = if ($hasNvidiaGpu) { 'GPU' } else { 'CPU' }
    }
    if (-not (Confirm-Yes "Install with backend '$Backend'?")) {
        $input = Read-Host 'Enter backend (GPU/CPU)'
        if ($input -match '^(GPU|CPU)$') { $Backend = $input.ToUpper() }
    }

    Write-Step "Install plan: dir=$MinerUDir | models=$ModelDir | backend=$Backend"
    if (-not (Confirm-Yes 'Proceed with install?')) {
        Write-Host 'USER_ABORTED'
        return 4
    }

    $venvPy = Join-Path $MinerUDir '.venv\Scripts\python.exe'

    # 1. create venv
    Write-Step 'Creating virtualenv...'
    try {
        & $python.Path -m venv (Join-Path $MinerUDir '.venv')
        if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
    } catch {
        Write-Warn "venv creation failed: $($_.Exception.Message)"
        return 3
    }

    # 2. pip install mineru
    Write-Step 'Installing mineru via pip...'
    $pipArgs = @('-m', 'pip', 'install', '--upgrade', 'pip')
    & $venvPy @pipArgs 2>&1 | Out-Host
    if (-not (Confirm-Yes 'Use Tencent PyPI mirror for faster download in China?')) {
        $useMirror = $false
    } else { $useMirror = $true }

    $installArgs = @('-m', 'pip', 'install', 'mineru')
    if ($useMirror) { $installArgs += @('-i', 'https://mirrors.cloud.tencent.com/pypi/simple') }
    & $venvPy @installArgs 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'mineru pip install failed. Check network / mirror, then rerun.'
        return 3
    }

    # 3. torch install
    Write-Step "Installing torch for backend '$Backend'..."
    if ($Backend -eq 'GPU') {
        Write-Warn 'GPU torch (cu124) may fail from China via official index (download.pytorch.org blocked).'
        if (Confirm-Yes 'Try pip cu124 index now? (If it fails, see docs/DEPLOYMENT.md manual steps)') {
            & $venvPy -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warn 'torch cu124 auto-install failed. Follow docs/DEPLOYMENT.md manual install, then rerun this script with -Scan to verify.'
                return 3
            }
        } else {
            Write-Warn 'Skipping torch auto-install. Follow docs/DEPLOYMENT.md manual steps, then rerun -Scan.'
            return 3
        }
    } else {
        $cpuArgs = @('-m', 'pip', 'install', 'torch', 'torchvision', '--index-url', 'https://download.pytorch.org/whl/cpu')
        if ($useMirror) {
            $cpuArgs = @('-m', 'pip', 'install', 'torch', 'torchvision')
        }
        & $venvPy @cpuArgs 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'torch CPU install failed.'
            return 3
        }
    }

    # 4. onnxruntime-gpu (optional)
    if ($Backend -eq 'GPU') {
        if (Confirm-Yes 'Install onnxruntime-gpu (CUDA EP, recommended for pipeline GPU)?') {
            $ortArgs = @('-m', 'pip', 'install', 'onnxruntime-gpu')
            if ($useMirror) { $ortArgs += @('-i', 'https://mirrors.cloud.tencent.com/pypi/simple') }
            & $venvPy @ortArgs 2>&1 | Out-Host
        }
    }

    # 5. download models
    Write-Step "Downloading models to $ModelDir via modelscope..."
    New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null
    & $venvPy -m mineru.cli.models_download -s modelscope -m all 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Model download failed. Check network, then rerun.'
        return 3
    }

    # 6. write mineru.json
    Write-Step 'Writing mineru.json...'
    $conf = @{
        'bucket_info'            = @{ 'bucket-name-1' = @('ak', 'sk', 'endpoint'); 'bucket-name-2' = @('ak', 'sk', 'endpoint') }
        'latex-delimiter-config' = @{
            display = @{ left = '$$'; right = '$$' }
            inline  = @{ left = '$'; right = '$' }
        }
        'llm-aided-config'       = @{
            title_aided = @{
                api_key        = 'your_api_key'
                base_url       = 'https://dashscope.aliyuncs.com/compatible-mode/v1'
                model          = 'qwen3.5-plus'
                enable_thinking = $false
                enable         = $false
            }
        }
        'models-dir'             = @{ pipeline = $ModelDir; vlm = '' }
        'model-source'           = 'modelscope'
        'config_version'         = '1.3.2'
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Join-Path $MinerUDir 'mineru.json') -Value $conf -Encoding UTF8

    # 7. write mineru.bat
    Write-Step 'Writing mineru.bat wrapper...'
    $batContent = @"
@echo off
setlocal
set "MINERU_TOOLS_CONFIG_JSON=$MinerUDir\mineru.json"
set "MINERU_MODEL_SOURCE=modelscope"
set "MINERU_DEVICE_MODE=$($(if ($Backend -eq 'GPU') { 'cuda' } else { 'cpu' }))"
set "CUDA_PATH=$MinerUDir\cuda_stub"
"$MinerUDir\.venv\Scripts\mineru.exe" %*
endlocal
"@
    Set-Content -LiteralPath (Join-Path $MinerUDir 'mineru.bat') -Value $batContent -Encoding ASCII

    # 8. write mineru.config.json for parse.ps1
    Write-Step 'Writing mineru.config.json for parse.ps1...'
    $parseConf = @{ mineruBat = (Join-Path $MinerUDir 'mineru.bat'); venvPython = $venvPy } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $here 'mineru.config.json') -Value $parseConf -Encoding UTF8

    Write-Host "[deploy][ok] Install complete at $MinerUDir"
    Write-Host "[deploy] Run:  & scripts\parse.ps1 -Paths <file>  to verify"
    Write-Host 'DONE_MinerU_INSTALLED'
    return 0
}

# ---------- main ----------
if ($Install) {
    exit (Invoke-Install)
}
else {
    exit (Invoke-Scan)
}
