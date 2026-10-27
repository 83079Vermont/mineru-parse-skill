#!/usr/bin/env bash
# MinerU parsing wrapper for Linux/WSL/macOS: cache, batch, cleanup, validation
# Bash port of parse.ps1 (MinerU 4.0) — identical CLI semantics and output markers.
#
# MinerU 4.0 CLI (verified against 4.0.12 `mineru-kit parse --help`):
#   mineru-kit parse <inputs...> -o <path> [--tier flash|basic|standard|advanced]
#                                  [--pages '1-5,8,r3-r1'|all] [--format markdown|middle_json|zip]
#                                  [--ocr-mode auto|txt|ocr] [--disable-image-analysis] [-v]
#
# Output markers (same as parse.ps1):
#   MINERU_UNAVAILABLE | NO_SUPPORTED_FILES | CACHED | PAGES | RUNNING
#   RECOMMENDED_TIMEOUT_SECONDS | MINERU_ERROR | NO_MD | RESULT | WARNING_EMPTY | DONE
#
# Usage:
#   scripts/parse.sh -Paths <file1> [file2 ...] [-OutDir <dir>] [-Tier auto|flash|basic|standard|advanced]
#                    [-Pages '1-5,8'] [-Format markdown|middle_json|zip] [-OcrMode auto|txt|ocr]
#                    [-NoImageAnalysis] [-Force] [-KeepImages]
#
# MinerU resolution chain (Linux config, does not touch Windows mineru.config.json):
#   env MINERU_KIT_BIN -> <scriptdir>/mineru.config.linux.json -> ~/.config/mineru/mineru.config.linux.json
#   -> sibling of MINERU_BIN -> PATH:mineru-kit

set -u
LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- args ----------
Paths=()
OutDir=""
Tier="auto"
Pages=""
Format="markdown"
OcrMode="auto"
NoImageAnalysis=0
Force=0
KeepImages=0
Backend=""; Method=""; ocrLang=""; Effort=""; NoFormula=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Paths|--paths)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do Paths+=("$1"); shift; done ;;
        -OutDir|--outdir)       OutDir="$2"; shift 2 ;;
        -Tier|--tier)           Tier="$2"; shift 2 ;;
        -Pages|--pages)         Pages="$2"; shift 2 ;;
        -Format|--format)       Format="$2"; shift 2 ;;
        -OcrMode|--ocr-mode)    OcrMode="$2"; shift 2 ;;
        -NoImageAnalysis|--no-image-analysis) NoImageAnalysis=1; shift ;;
        -Force|--force)         Force=1; shift ;;
        -KeepImages|--keep-images) KeepImages=1; shift ;;
        # deprecated 3.x parameters
        -Backend|--backend)     Backend="$2"; shift 2 ;;
        -Method|--method)       Method="$2"; shift 2 ;;
        -Lang|--lang)           ocrLang="$2"; shift 2 ;;
        -Effort|--effort)       Effort="$2"; shift 2 ;;
        -NoFormula|--no-formula) NoFormula=1; shift ;;
        -h|--help)              grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "UNKNOWN_ARG	$1" >&2; exit 1 ;;
    esac
done

case "$Tier"   in auto|flash|basic|standard|advanced) ;; *) echo "BAD_TIER	$Tier" >&2; exit 1 ;; esac
case "$Format" in markdown|middle_json|zip) ;; *) echo "BAD_FORMAT	$Format" >&2; exit 1 ;; esac
case "$OcrMode" in auto|txt|ocr) ;; *) echo "BAD_OCR_MODE	$OcrMode" >&2; exit 1 ;; esac

# ---------- deprecated 3.x mapping ----------
if [[ -n "$Backend" ]]; then
    case "${Backend,,}" in
        pipeline)      Tier="basic" ;;
        hybrid-engine|vlm-engine) Tier="standard" ;;
        auto)          : ;;
        *) echo "WARN_DEPRECATED	-Backend $Backend is a 3.x backend; 4.0 uses --tier" >&2 ;;
    esac
    echo "WARN_DEPRECATED	-Backend mapped to -Tier $Tier" >&2
fi
[[ -n "$Method" ]] && { OcrMode="$Method"; echo "WARN_DEPRECATED	-Method mapped to -OcrMode $OcrMode" >&2; }
[[ -n "$ocrLang" ]] && echo "WARN_DEPRECATED	-Lang has no 4.0 equivalent (OCR language is automatic); ignored" >&2
if [[ -n "$Effort" ]]; then
    [[ "${Effort,,}" == "high" && ( "$Tier" == "basic" || "$Tier" == "auto" ) ]] && Tier="advanced"
    echo "WARN_DEPRECATED	-Effort is gone in 4.0; use -Tier advanced (now: $Tier)" >&2
fi
[[ "$NoFormula" == "1" ]] && { NoImageAnalysis=1; echo "WARN_DEPRECATED	-NoFormula mapped to --disable-image-analysis" >&2; }
[[ "$KeepImages" == "1" ]] && echo "WARN_DEPRECATED	-KeepImages: markdown output inlines images as base64; use -Format zip for image files" >&2

# ---------- resolve mineru ----------
json_str() { # json_str <file> <key>
    sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1
}

MineruBin=""
KitBin=""
VenvPy=""
if [[ -n "${MINERU_BIN:-}" && -x "${MINERU_BIN:-}" ]]; then
    MineruBin="$MINERU_BIN"
else
    for cfg in "$SCRIPT_DIR/mineru.config.linux.json" "$(dirname "$SCRIPT_DIR")/mineru.config.linux.json" "$HOME/.config/mineru/mineru.config.linux.json"; do
        if [[ -f "$cfg" ]]; then
            cand="$(json_str "$cfg" mineruBin)"
            if [[ -n "$cand" && -x "$cand" ]]; then
                MineruBin="$cand"
                VenvPy="$(json_str "$cfg" venvPython)"
                break
            fi
        fi
    done
fi
if [[ -z "$MineruBin" ]] && command -v mineru >/dev/null 2>&1; then
    MineruBin="$(command -v mineru)"
fi

# kit entrypoint (preferred for parsing): env -> config -> sibling -> PATH
if [[ -n "${MINERU_KIT_BIN:-}" && -x "${MINERU_KIT_BIN:-}" ]]; then
    KitBin="$MINERU_KIT_BIN"
else
    for cfg in "$SCRIPT_DIR/mineru.config.linux.json" "$(dirname "$SCRIPT_DIR")/mineru.config.linux.json" "$HOME/.config/mineru/mineru.config.linux.json"; do
        [[ -f "$cfg" ]] || continue
        cand="$(json_str "$cfg" mineruKitBin)"
        if [[ -n "$cand" && -x "$cand" ]]; then KitBin="$cand"; break; fi
    done
fi
if [[ -z "$KitBin" && -n "$MineruBin" ]]; then
    bdir="$(dirname "$MineruBin")"
    for c in "$bdir/mineru-kit" "$bdir/../.venv/bin/mineru-kit"; do
        [[ -x "$c" ]] && { KitBin="$c"; break; }
    done
fi
[[ -z "$KitBin" ]] && command -v mineru-kit >/dev/null 2>&1 && KitBin="$(command -v mineru-kit)"

if [[ -z "$KitBin" ]]; then
    echo "MINERU_UNAVAILABLE"
    exit 3
fi
if [[ -z "$VenvPy" || ! -x "$VenvPy" ]]; then
    bdir="$(dirname "$KitBin")"
    for c in "$bdir/../.venv/bin/python" "$bdir/../../.venv/bin/python" "$bdir/python"; do
        [[ -x "$c" ]] && { VenvPy="$c"; break; }
    done
fi

# ---------- filter supported files ----------
supported=" pdf docx pptx xlsx jpg jpeg png bmp tif tiff "
files=()
for p in "${Paths[@]:-}"; do
    [[ -z "$p" ]] && continue
    if [[ "$p" = /* || "$p" == ./* || "$p" == ../* ]]; then rp="$p"; else rp="$PWD/$p"; fi
    [[ -f "$rp" ]] || continue
    ext="${rp##*.}"; ext="${ext,,}"
    [[ "$supported" == *" $ext "* ]] && files+=("$rp")
done
if [[ ${#files[@]} -eq 0 ]]; then
    echo "NO_SUPPORTED_FILES"
    exit 4
fi

# ---------- out dir ----------
useTempOut=0
tmpOutRoot=""
if [[ -z "$OutDir" ]]; then
    if [[ ${#files[@]} -eq 1 ]]; then
        OutDir="$(dirname "${files[0]}")"
    else
        OutDir="$(mktemp -d "${TMPDIR:-/tmp}/mineru_out_XXXXXX")"
        useTempOut=1; tmpOutRoot="$OutDir"
    fi
fi
mkdir -p "$OutDir"

# ---------- helpers ----------
get_page_count() {
    local f="$1" ext n
    ext="${f##*.}"; ext="${ext,,}"
    [[ "$ext" != "pdf" ]] && { echo 1; return; }
    if [[ -n "$VenvPy" && -x "$VenvPy" ]]; then
        n="$("$VenvPy" -c "import sys; from pypdfium2 import PdfDocument; print(len(PdfDocument(sys.argv[1])))" "$f" 2>/dev/null | tail -1)" || n=""
        if [[ "$n" =~ ^[0-9]+$ ]]; then echo "$n"; return; fi
    fi
    echo 1
}

find_artifact() { # <outRoot> <stem> <ext>
    local root="$1" stem="$2" ext="$3" direct="$1/$2$3"
    [[ -f "$direct" ]] && { echo "$direct"; return; }
    find "$root" -type f -name "*$ext" 2>/dev/null | while IFS= read -r m; do
        [[ "$(basename "$m" "$ext")" == "$stem" ]] && { echo "$m"; break; }
    done
}

# ---------- cache check ----------
declare -a cachedSrc=() cachedMd=()
declare -a toParse=()
for f in "${files[@]}"; do
    parent="$(dirname "$f")"; base="$(basename "$f")"; stem="${base%.*}"
    candidates=()
    [[ -f "$OutDir/$stem.md" ]] && candidates+=("$OutDir/$stem.md")
    [[ -f "$parent/$stem.md" ]] && candidates+=("$parent/$stem.md")
    if [[ -d "$OutDir" ]]; then
        while IFS= read -r m; do
            [[ -n "$m" && "$(basename "$m" .md)" == "$stem" ]] && candidates+=("$m")
        done < <(find "$OutDir" -type f -name '*.md' 2>/dev/null)
    fi
    hit=""
    for c in "${candidates[@]:-}"; do
        [[ -z "$c" || ! -f "$c" ]] && continue
        if [[ ! "$f" -nt "$c" ]]; then hit="$c"; break; fi
    done
    if [[ -n "$hit" && "$Force" == "0" ]]; then
        cachedSrc+=("$f"); cachedMd+=("$hit")
        printf 'CACHED\t%s\t%s\n' "$f" "$hit"
    else
        toParse+=("$f")
    fi
done

# ---------- staging for batch ----------
stagingDir=""
declare -a jobSrc=() jobStem=()
inputPath=""
if [[ ${#toParse[@]} -gt 1 ]]; then
    stagingDir="$(mktemp -d "${TMPDIR:-/tmp}/mineru_stage_XXXXXX")"
    i=1
    for f in "${toParse[@]}"; do
        base="$(basename "$f")"
        stageName="${i}_${base}"
        cp -f "$f" "$stagingDir/$stageName" 2>/dev/null
        jobSrc+=("$f"); jobStem+=("${stageName%.*}")
        i=$((i+1))
    done
    inputPath="$stagingDir"
elif [[ ${#toParse[@]} -eq 1 ]]; then
    f="${toParse[0]}"; base="$(basename "$f")"
    jobSrc+=("$f"); jobStem+=("${base%.*}")
    inputPath="$f"
fi

# ---------- tier auto + timeout ----------
totalPages=0
for f in "${jobSrc[@]:-}"; do
    [[ -z "$f" ]] && continue
    totalPages=$(( totalPages + $(get_page_count "$f") ))
done
effectiveTier="$Tier"
if [[ ${#jobSrc[@]} -eq 0 ]]; then
    effectiveTier="-"          # nothing to parse (all cached)
elif [[ "$effectiveTier" == "auto" ]]; then
    allPdf=1
    for f in "${jobSrc[@]}"; do
        ext="${f##*.}"; ext="${ext,,}"
        [[ "$ext" != "pdf" ]] && allPdf=0
    done
    if [[ "$allPdf" == "0" ]]; then effectiveTier="flash"
    elif [[ "$totalPages" -lt 10 ]]; then effectiveTier="basic"
    else effectiveTier="standard"; fi
fi
case "$effectiveTier" in
    flash) perPage=3 ;;
    basic) perPage=8 ;;
    *)     perPage=15 ;;
esac
printf 'PAGES\t%s\tTIER=%s\tFORMAT=%s\n' "$totalPages" "$effectiveTier" "$Format"
echo "RECOMMENDED_TIMEOUT_SECONDS=$(( 30 + totalPages * perPage ))"

# ---------- run mineru-kit ----------
if [[ ${#jobSrc[@]} -gt 0 ]]; then
    if [[ ${#jobSrc[@]} -eq 1 && "$Format" == "markdown" ]]; then
        outTarget="$OutDir/${jobStem[0]}.md"
    else
        outTarget="$OutDir"
    fi

    margs=(parse "$inputPath" -o "$outTarget" --tier "$effectiveTier" --format "$Format" --ocr-mode "$OcrMode")
    [[ -n "$Pages" ]] && margs+=(--pages "$Pages")
    [[ "$NoImageAnalysis" == "1" ]] && margs+=(--disable-image-analysis)

    printf 'RUNNING\t%s\t->\t%s\n' "$(IFS='; '; echo "${jobSrc[*]}")" "$outTarget"
    "$KitBin" "${margs[@]}"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        printf 'MINERU_ERROR\t%s\n' "$rc"
        [[ -n "$stagingDir" ]] && rm -rf "$stagingDir"
        [[ "$useTempOut" == "1" ]] && rm -rf "$tmpOutRoot"
        exit 5
    fi

    keepEff=$KeepImages
    [[ "$useTempOut" == "0" ]] && keepEff=1
    case "$Format" in zip) ext=".zip" ;; middle_json) ext=".json" ;; *) ext=".md" ;; esac
    for idx in "${!jobSrc[@]}"; do
        src="${jobSrc[$idx]}"; stem="${jobStem[$idx]}"
        srcBase="$(basename "$src")"; srcStem="${srcBase%.*}"; srcParent="$(dirname "$src")"
        artifact="$(find_artifact "$OutDir" "$stem" "$ext")"
        if [[ -z "$artifact" || ! -f "$artifact" ]]; then
            printf 'NO_MD\t%s\n' "$src"
            continue
        fi
        if [[ "$useTempOut" == "1" ]]; then
            dest="$srcParent/$srcStem$ext"
            cp -f "$artifact" "$dest"
            artifact="$dest"
            rm -rf "$OutDir/$stem"
        fi
        bytes=$(stat -c%s "$artifact" 2>/dev/null || echo 0)
        lines=0
        [[ "$ext" == ".md" ]] && lines=$(wc -l < "$artifact" 2>/dev/null || echo 0)
        printf 'RESULT\t%s\t%s\t%s\t%s\n' "$src" "$artifact" "$bytes" "$lines"
        [[ "$ext" == ".md" && "$bytes" -lt 1024 ]] && printf 'WARNING_EMPTY\t%s\n' "$src"
    done
fi

# ---------- final cleanup ----------
[[ -n "$stagingDir" ]] && rm -rf "$stagingDir"
[[ "$useTempOut" == "1" ]] && rm -rf "$tmpOutRoot"
printf 'DONE\tparsed=%s\tcached=%s\n' "${#jobSrc[@]}" "${#cachedSrc[@]}"
exit 0
