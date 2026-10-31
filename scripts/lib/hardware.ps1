# Hardware / runtime probing helpers for deploy.ps1 (dot-sourced).
#
# Kept separate so deploy.ps1 stays focused on scan-and-install orchestration.
# Functions: Get-GpuInfo, Get-CpuInfo, Get-RamInfo, Get-DiskFree, Get-PythonInfo, Get-NvidiaSmi

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
