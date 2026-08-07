# Generate harness-native copies of the mineru-parse skill from a single source.
#
# Usage:
#   & scripts\generate-harnesses.ps1 -Harness all
#   & scripts\generate-harnesses.ps1 -Harness opencode,claude,cline
#   & scripts\generate-harnesses.ps1 -Harness cherrystudio
#   & scripts\generate-harnesses.ps1 -Harness zcode
#   & scripts\generate-harnesses.ps1 -Harness opencode -TargetDir D:\out\test
#   & scripts\generate-harnesses.ps1 -Harness all -Scope project
#   & scripts\generate-harnesses.ps1 -Harness all -Force
#
# Options:
#   -Harness   comma-separated harness names or 'all'. Default: all
#   -TargetDir explicit output dir (overrides registry userDir/projectDir). Useful for dry-run.
#   -Scope     'user' or 'project'. If omitted and using registry paths, prompts interactively.
#   -Force     overwrite existing files.

param(
    [string[]]$Harness = @('all'),
    [string]$TargetDir = '',
    [ValidateSet('user', 'project', '')]
    [string]$Scope = '',
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $here
$registryPath = Join-Path $skillRoot 'harnesses\registry.json'

function Expand-UserPath([string]$p) {
    if ($p -like '~/*' -or $p -like '~\*') {
        return Join-Path $env:USERPROFILE ($p.Substring(2).Replace('/', '\'))
    }
    return $p
}

function Invoke-CopyTree([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $src)) { return }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $dest = Join-Path $dst $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        if ((Test-Path -LiteralPath $dest) -and -not $Force) { return }
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
    }
}

if (-not (Test-Path -LiteralPath $registryPath)) {
    Write-Host "REGISTRY_MISSING $registryPath"
    exit 3
}
$registry = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if (-not $registry.harnesses) {
    Write-Host 'REGISTRY_INVALID no harnesses key'
    exit 3
}

$flatNames = @()
foreach ($hItem in $Harness) {
    $flatNames += @($hItem -split ',' | ForEach-Object { $_.Trim() })
}
$names = if ($flatNames.Count -eq 1 -and $flatNames[0] -eq 'all') {
    @($registry.harnesses.PSObject.Properties.Name)
} else {
    $flatNames
}
foreach ($n in $names) {
    $h = $registry.harnesses.($n)
    if (-not $h) {
        Write-Host "UNKNOWN_HARNESS $n"
        continue
    }

    # Resolve effective spec (reuse for compatible harnesses)
    if ($h.reuse) {
        $base = $registry.harnesses.($h.reuse)
        $effective = [pscustomobject]@{
            frontmatter = $base.frontmatter
            format      = $base.format
            notes       = $h.notes
        }
        $userDir = if ($h.userDir) { $h.userDir } else { $base.userDir }
        $projectDir = if ($h.projectDir) { $h.projectDir } else { $base.projectDir }
        $status = $h.status
    } else {
        $effective = $h
        $userDir = $h.userDir
        $projectDir = $h.projectDir
        $status = $h.status
    }

    # Resolve target dir
    $target = ''
    if ($TargetDir) {
        $target = $TargetDir
    } else {
        $scope = $Scope
        if (-not $scope) {
            $scope = (Read-Host "Scope for '$n' (user/project)").ToLower()
            if ($scope -notin @('user', 'project')) { $scope = 'user' }
        }
        $target = if ($scope -eq 'project') { $projectDir } else { $userDir }
        $target = Expand-UserPath $target
    }

    Write-Host "GENERATING $n -> $target [status=$status format=$($effective.format)]"
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }

    # Read source SKILL.md, strip its own frontmatter
    $srcMd = [System.IO.File]::ReadAllText((Join-Path $skillRoot 'SKILL.md'), [System.Text.Encoding]::UTF8)
    $body = $srcMd
    if ($srcMd -match '(?s)^\s*---\r?\n.*?\r?\n---\r?\n(.*)$') {
        $body = $Matches[1]
    }
    $body = $body.TrimStart()

    # Build frontmatter
    $fmLines = @()
    foreach ($k in $effective.frontmatter.PSObject.Properties.Name) {
        $v = $effective.frontmatter.($k)
        $fmLines += ("{0}: {1}" -f $k, $v)
    }

    $outMd = if ($fmLines.Count -gt 0) {
        "---`n" + ($fmLines -join "`n") + "`n---`n" + "`n" + $body
    } else {
        $body
    }

    $mdDest = Join-Path $target 'SKILL.md'
    if ((Test-Path -LiteralPath $mdDest) -and -not $Force) {
        Write-Host "  SKIP existing SKILL.md at $mdDest (use -Force to overwrite)"
    } else {
        Set-Content -LiteralPath $mdDest -Value $outMd -Encoding UTF8
        Write-Host "  wrote $mdDest"
    }

    # Copy scripts/ and docs/ (keep relative structure)
    foreach ($sub in @('scripts', 'docs')) {
        $srcSub = Join-Path $skillRoot $sub
        if (Test-Path -LiteralPath $srcSub) {
            Invoke-CopyTree $srcSub (Join-Path $target $sub)
            Write-Host "  copied $sub\"
        }
    }

    # Codex 8KB check
    if ($n -eq 'codex' -and (Test-Path -LiteralPath $mdDest)) {
        $size = (Get-Item -LiteralPath $mdDest).Length
        if ($size -gt 8192) { Write-Host "  WARNING codex SKILL.md exceeds 8KB ($size bytes)" }
        else { Write-Host "  codex SKILL.md = $size bytes (<=8KB OK)" }
    }

    if ($status -eq 'extension-point') {
        Write-Host "  NOTE: $($h.notes) Fill registry.json frontmatter/format to enable native generation."
    }
}

Write-Host 'DONE'
exit 0
