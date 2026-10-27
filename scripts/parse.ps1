# MinerU parsing wrapper (Windows): cache, batch, cleanup, validation
#
# MinerU 4.0 CLI (verified against 4.0.12 `mineru-kit parse --help`):
#   mineru-kit parse <inputs...> -o <path> [--tier flash|basic|standard|advanced]
#                                  [--pages '1-5,8,r3-r1'|all] [--format markdown|middle_json|zip]
#                                  [--ocr-mode auto|txt|ocr] [--disable-image-analysis] [-v]
#
# Output semantics (measured):
#   single file + -o <file>.md   -> that exact file
#   single file + -o <dir>       -> <dir>/<stem>.md
#   directory   + -o <dir>       -> <dir>/<each stem>.md
#   --format zip                 -> <dir>/<stem>.zip  (markdown.md, images/, middle_json.json, ...)
#   --format markdown            -> single .md, images inlined as base64 data URIs (no side files)
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Paths,

    [string]$OutDir,

    # 4.0 quality tier. auto: Office/image -> flash; PDF <10 pages -> basic; else standard.
    [ValidateSet('auto', 'flash', 'basic', 'standard', 'advanced')]
    [string]$Tier = 'auto',

    # PDF page range, e.g. '1-5,8' / 'r3-r1' / 'all'. Empty = MinerU default (all pages).
    [string]$Pages = '',

    [ValidateSet('markdown', 'middle_json', 'zip')]
    [string]$Format = 'markdown',

    [ValidateSet('auto', 'txt', 'ocr')]
    [string]$OcrMode = 'auto',

    [switch]$NoImageAnalysis,

    [switch]$Force,

    # Deprecated in 4.0: markdown output inlines images as base64, so there is no images/ dir to keep.
    [switch]$KeepImages,

    # ---- deprecated 3.x parameters (accepted for compatibility; mapped or warned) ----
    [string]$Backend = '',
    [string]$Method = '',
    [string]$Lang = '',
    [string]$Effort = '',
    [switch]$NoFormula
)

function Resolve-MineruPaths {
    $scriptDir = $PSScriptRoot
    $configPath = $null
    # config may sit next to the script (deploy.ps1 writes it there) or at the skill root
    foreach ($c in @(
            (Join-Path $scriptDir 'mineru.config.json'),
            (Join-Path (Split-Path -Parent $scriptDir) 'mineru.config.json'),
            (Join-Path (Join-Path $env:USERPROFILE '.config\mineru') 'mineru.config.json'))) {
        if (Test-Path -LiteralPath $c) { $configPath = $c; break }
    }
    $config = $null
    if ($configPath) {
        try { $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } catch { }
    }

    $mineruBat = $null
    $venvPy = $null
    if ($env:MINERU_BAT) {
        $mineruBat = $env:MINERU_BAT
    }
    elseif ($config -and $config.mineruBat) {
        $mineruBat = $config.mineruBat
    }
    elseif (Test-Path 'D:\MinerU\mineru.bat') {
        $mineruBat = 'D:\MinerU\mineru.bat'
    }
    elseif (Get-Command mineru -ErrorAction SilentlyContinue) {
        $mineruBat = (Get-Command mineru).Source
    }
    if (-not $mineruBat) { return $null }

    if ($config -and $config.venvPython) {
        $venvPy = $config.venvPython
    }
    else {
        $base = Split-Path -Parent $mineruBat
        $cand = Join-Path (Join-Path $base '.venv\Scripts') 'python.exe'
        if (Test-Path -LiteralPath $cand) { $venvPy = $cand }
    }

    # --- 4.0 kit entrypoint: env -> config -> sibling of mineru.bat -> PATH ---
    $kitBat = $null
    if ($env:MINERU_KIT_BAT) {
        $kitBat = $env:MINERU_KIT_BAT
    }
    elseif ($config -and $config.mineruKitBat) {
        $kitBat = $config.mineruKitBat
    }
    else {
        $base = Split-Path -Parent $mineruBat
        foreach ($cand in @('mineru-kit.bat', 'mineru-kit.cmd', 'mineru-kit.exe')) {
            $p = Join-Path $base $cand
            if (Test-Path -LiteralPath $p) { $kitBat = $p; break }
        }
        if (-not $kitBat) {
            $baseDot = Split-Path -Parent $base
            $p = Join-Path (Join-Path $baseDot '.venv\Scripts') 'mineru-kit.exe'
            if (Test-Path -LiteralPath $p) { $kitBat = $p }
        }
    }
    if (-not $kitBat) {
        $cmd = Get-Command mineru-kit -ErrorAction SilentlyContinue
        if ($cmd) { $kitBat = $cmd.Source }
    }
    if (-not $kitBat) { return $null }

    return [pscustomobject]@{ MineruBat = $mineruBat; MineruKit = $kitBat; VenvPy = $venvPy }
}

$mineru = Resolve-MineruPaths
if (-not $mineru) {
    Write-Host 'MINERU_UNAVAILABLE'
    exit 3
}
$mineruKit = $mineru.MineruKit
$venvPy = $mineru.VenvPy

# ---- deprecated parameter mapping (3.x -> 4.0) ----
if ($Backend) {
    switch ($Backend.ToLower()) {
        'pipeline' { $Tier = 'basic' }
        'hybrid-engine' { $Tier = 'standard' }
        'vlm-engine' { $Tier = 'standard' }
        'auto' { }
        default { Write-Host ("WARN_DEPRECATED`t-Backend {0} is a 3.x backend; 4.0 uses --tier" -f $Backend) }
    }
    Write-Host ("WARN_DEPRECATED`t-Backend mapped to -Tier {0}" -f $Tier)
}
if ($Method) {
    $OcrMode = $Method
    Write-Host ("WARN_DEPRECATED`t-Method mapped to -OcrMode {0}" -f $OcrMode)
}
if ($Lang) { Write-Host "WARN_DEPRECATED`t-Lang has no 4.0 equivalent (OCR language is automatic); ignored" }
if ($Effort) {
    if ($Effort.ToLower() -eq 'high' -and $Tier -in @('basic', 'auto')) { $Tier = 'advanced' }
    Write-Host ("WARN_DEPRECATED`t-Effort is gone in 4.0; use -Tier advanced (now: {0})" -f $Tier)
}
if ($NoFormula) {
    $NoImageAnalysis = $true
    Write-Host 'WARN_DEPRECATED\t-NoFormula mapped to --disable-image-analysis'
}
if ($KeepImages) {
    Write-Host 'WARN_DEPRECATED\t-KeepImages: markdown output inlines images as base64; use -Format zip for image files'
}

# ---- sandbox compatibility (DSH): os.mkdir(path, mode) creates an unreadable dir; patch it ----
$sandboxFix = Join-Path $PSScriptRoot 'sandbox'
if (Test-Path -LiteralPath (Join-Path $sandboxFix 'sitecustomize.py')) {
    $env:PYTHONPATH = if ($env:PYTHONPATH) { "$sandboxFix;$env:PYTHONPATH" } else { $sandboxFix }
}

$supported = @('.pdf', '.docx', '.pptx', '.xlsx', '.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff')
$files = @()
foreach ($p in $Paths) {
    $resolved = Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $resolved) { continue }
    $ext = [IO.Path]::GetExtension($resolved.Path).ToLower()
    if ($supported -contains $ext) { $files += $resolved.Path }
}
if ($files.Count -eq 0) {
    Write-Host 'NO_SUPPORTED_FILES'
    exit 4
}

$useTempOut = $false
if (-not $OutDir) {
    if ($files.Count -eq 1) {
        $OutDir = Split-Path -Parent $files[0]
    }
    else {
        $OutDir = Join-Path $env:TEMP ("mineru_out_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        $useTempOut = $true
    }
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

function Get-PageCount([string]$filePath) {
    if ([IO.Path]::GetExtension($filePath).ToLower() -ne '.pdf') { return 1 }
    if ($venvPy -and (Test-Path -LiteralPath $venvPy)) {
        try {
            $out = & $venvPy -c "import sys; from pypdfium2 import PdfDocument; d=PdfDocument(sys.argv[1]); print(len(d))" $filePath 2>$null
            $last = @($out | Select-Object -Last 1)
            if ($last.Count -gt 0) {
                $n = 0
                if ([int]::TryParse([string]$last[0], [ref]$n)) { return $n }
            }
        }
        catch { }
    }
    return 1
}

# Locate the produced markdown (or zip) for a given stem.
function Find-Artifact([string]$outRoot, [string]$stem, [string]$ext) {
    $direct = Join-Path $outRoot ($stem + $ext)
    if (Test-Path -LiteralPath $direct) { return $direct }
    $hits = @(Get-ChildItem -LiteralPath $outRoot -Recurse -File -Filter ("*" + $ext) -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq $stem })
    if ($hits.Count -eq 0) { return $null }
    return ($hits | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# In markdown mode MinerU writes only the .md — there are no aux files to clean.
# In zip/middle_json mode the archive IS the deliverable, so it is left in place.
function Invoke-OutputCleanup([string]$stemDir, [bool]$keepImgs, [string]$fmt) {
    if ($fmt -eq 'markdown') { return }
    if (-not (Test-Path -LiteralPath $stemDir)) { return }
    if ($keepImgs) { return }
    # only tidy genuinely empty directories left behind
    $dirs = @(Get-ChildItem -LiteralPath $stemDir -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($d in $dirs) {
        if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

$cached = @()
$toParse = @()
foreach ($f in $files) {
    $parent = Split-Path -Parent $f
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $candidates = @()
    # cache candidates: explicit out path, then the source directory copy
    foreach ($c in @((Join-Path $OutDir ($stem + '.md')), (Join-Path $parent ($stem + '.md')))) {
        if (Test-Path -LiteralPath $c) { $candidates += $c }
    }
    if (Test-Path -LiteralPath $OutDir) {
        $mds = @(Get-ChildItem -LiteralPath $OutDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
        foreach ($m in $mds) {
            if ($m.BaseName -eq $stem) { $candidates += $m.FullName }
        }
    }
    $hit = $null
    foreach ($c in ($candidates | Select-Object -Unique)) {
        try {
            if ((Get-Item -LiteralPath $c).LastWriteTime -ge (Get-Item -LiteralPath $f).LastWriteTime) {
                $hit = $c
                break
            }
        }
        catch { }
    }
    if ($hit -and -not $Force) {
        $cached += [pscustomobject]@{ Source = $f; Md = $hit }
        Write-Host ("CACHED`t{0}`t{1}" -f $f, $hit)
    }
    else {
        $toParse += [pscustomobject]@{ Source = $f }
    }
}

$stagingDir = $null
$jobs = @()
$inputPath = $null
if ($toParse.Count -gt 1) {
    $stagingDir = Join-Path $env:TEMP ("mineru_stage_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    $i = 1
    foreach ($job in $toParse) {
        $stageName = ("{0}_{1}" -f $i, [IO.Path]::GetFileName($job.Source))
        $target = Join-Path $stagingDir $stageName
        try { Copy-Item -LiteralPath $job.Source -Destination $target -Force } catch { }
        $job | Add-Member -NotePropertyName StageName -NotePropertyValue $stageName
        $i++
    }
    $inputPath = $stagingDir
    $jobs = $toParse
}
elseif ($toParse.Count -eq 1) {
    $toParse[0] | Add-Member -NotePropertyName StageName -NotePropertyValue ([IO.Path]::GetFileName($toParse[0].Source))
    $jobs = $toParse
    $inputPath = $toParse[0].Source
}

$totalPages = 0
foreach ($job in $jobs) { $totalPages += (Get-PageCount $job.Source) }

$effectiveTier = $Tier
if ($jobs.Count -eq 0) {
    $effectiveTier = '-'   # nothing to parse (all cached)
}
elseif ($effectiveTier -eq 'auto') {
    $allPdf = @($jobs | Where-Object { [IO.Path]::GetExtension($_.Source).ToLower() -eq '.pdf' }).Count -eq $jobs.Count
    if (-not $allPdf) { $effectiveTier = 'flash' }
    elseif ($totalPages -lt 10) { $effectiveTier = 'basic' }
    else { $effectiveTier = 'standard' }
}

# Timeout estimate (seconds), calibrated on measured runs; flash needs no models.
$perPage = switch ($effectiveTier) {
    'flash' { 3 }
    'basic' { 8 }
    default { 15 }
}
$timeout = [int](30 + ($totalPages * $perPage))
Write-Host ("PAGES`t{0}`tTIER={1}`tFORMAT={2}" -f $totalPages, $effectiveTier, $Format)
Write-Host ("RECOMMENDED_TIMEOUT_SECONDS={0}" -f $timeout)

if ($jobs.Count -gt 0) {
    # single markdown file -> -o points at the exact .md path; anything else -> -o is a directory
    if ($jobs.Count -eq 1 -and $Format -eq 'markdown') {
        $stem = [IO.Path]::GetFileNameWithoutExtension($jobs[0].StageName)
        $outTarget = Join-Path $OutDir ($stem + '.md')
    }
    else {
        $outTarget = $OutDir
    }

    $mineruArgs = @('parse', $inputPath, '-o', $outTarget, '--tier', $effectiveTier, '--format', $Format, '--ocr-mode', $OcrMode)
    if ($Pages) { $mineruArgs += @('--pages', $Pages) }
    if ($NoImageAnalysis) { $mineruArgs += '--disable-image-analysis' }

    Write-Host ("RUNNING`t{0}`t-> {1}" -f (($jobs | ForEach-Object { $_.Source }) -join '; '), $outTarget)
    & $mineruKit @mineruArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host ("MINERU_ERROR`t{0}" -f $exitCode)
        if ($stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($useTempOut) { Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction SilentlyContinue }
        exit 5
    }

    $keepImages = $KeepImages -or (-not $useTempOut)
    foreach ($job in $jobs) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($job.StageName)
        $ext = if ($Format -eq 'zip') { '.zip' } elseif ($Format -eq 'middle_json') { '.json' } else { '.md' }
        $artifact = Find-Artifact $OutDir $stem $ext
        if (-not $artifact) {
            Write-Host ("NO_MD`t{0}" -f $job.Source)
            continue
        }
        $stemDir = Join-Path $OutDir $stem
        if ($useTempOut) {
            $destParent = Split-Path -Parent $job.Source
            $dest = Join-Path $destParent ([IO.Path]::GetFileNameWithoutExtension($job.Source) + $ext)
            Copy-Item -LiteralPath $artifact -Destination $dest -Force
            $artifact = $dest
            Remove-Item -LiteralPath $stemDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Invoke-OutputCleanup $stemDir $keepImages $Format
        }
        $bytes = 0
        $lines = 0
        try {
            $bytes = (Get-Item -LiteralPath $artifact).Length
            if ($ext -eq '.md') { $lines = @(Get-Content -LiteralPath $artifact -ErrorAction SilentlyContinue).Count }
        }
        catch { }
        Write-Host ("RESULT`t{0}`t{1}`t{2}`t{3}" -f $job.Source, $artifact, $bytes, $lines)
        if ($ext -eq '.md' -and $bytes -lt 1024) { Write-Host ("WARNING_EMPTY`t{0}" -f $job.Source) }
    }
}

if ($stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
if ($useTempOut) { Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ("DONE`tparsed={0}`tcached={1}" -f $jobs.Count, $cached.Count)
exit 0
