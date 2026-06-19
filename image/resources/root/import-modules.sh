#!/bin/bash
# import-modules.sh — import OpenCms module zips via CmsShell replaceModule, in
# dependency order derived from each module's manifest.xml.
#
# Contract (consumed by downstream init.sh / bootstrap flows):
#   import-modules.sh --from-dir DIR [--recursive] \
#       --cmsshell /path/ROOT/WEB-INF/cmsshell.sh \
#       --user Admin --password admin --site / \
#       [--copy-to-default] [--base WEB-INF] [--run]
#
# Without --run it performs a dry run: prints the resolved install order and the
# generated CmsShell script, but does not execute, copy, or change anything.
#
# Dependency ordering: reads <dependency name="..."/> entries from each zip's
# manifest.xml and topologically sorts (dependencies imported first). Deps that
# are not among the supplied zips (core / already-installed modules) are ignored.
set -euo pipefail

log() { echo "[import-modules] $*"; }
die() { echo "[import-modules] ERROR: $*" >&2; exit 1; }

FROM_DIR=""
RECURSIVE=0
CMSSHELL=""
OC_USER="Admin"
OC_PASSWORD="admin"
SITE="/"
COPY_TO_DEFAULT=0
BASE=""
RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --from-dir)        FROM_DIR="$2"; shift 2 ;;
        --recursive)       RECURSIVE=1; shift ;;
        --cmsshell)        CMSSHELL="$2"; shift 2 ;;
        --user)            OC_USER="$2"; shift 2 ;;
        --password)        OC_PASSWORD="$2"; shift 2 ;;
        --site)            SITE="$2"; shift 2 ;;
        --copy-to-default) COPY_TO_DEFAULT=1; shift ;;
        --base)            BASE="$2"; shift 2 ;;
        --run)             RUN=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$FROM_DIR" ] || die "--from-dir is required"
[ -d "$FROM_DIR" ] || die "--from-dir not a directory: $FROM_DIR"

# --- discover zips ---
declare -a ZIPS=()
if [ "$RECURSIVE" -eq 1 ]; then
    while IFS= read -r -d '' z; do ZIPS+=("$z"); done \
        < <(find "$FROM_DIR" -type f -name '*.zip' -print0)
else
    shopt -s nullglob
    ZIPS=("$FROM_DIR"/*.zip)
    shopt -u nullglob
fi

[ "${#ZIPS[@]}" -gt 0 ] || { log "no .zip files under $FROM_DIR — nothing to do"; exit 0; }

# --- manifest.xml helpers ---
# module name = first <name>…</name> in the manifest (the module element's own name)
module_name_of() {
    unzip -p "$1" manifest.xml 2>/dev/null | tr -d '\r' \
        | awk 'match($0,/<name>[^<]*<\/name>/){s=$0;sub(/.*<name>/,"",s);sub(/<\/name>.*/,"",s);print s;exit}'
}
deps_of() {
    unzip -p "$1" manifest.xml 2>/dev/null | tr -d '\r' \
        | grep -oE '<dependency[[:space:]]+name="[^"]+"' \
        | sed -E 's/.*name="([^"]+)".*/\1/'
}

# --- map module name -> zip (highest version wins on duplicate) ---
declare -A ZIP_OF=()
declare -A DEPS_OF=()
for z in "${ZIPS[@]}"; do
    name="$(module_name_of "$z")" || true
    if [ -z "$name" ]; then
        log "WARNING: no module name in $z — skipping"
        continue
    fi
    if [ -n "${ZIP_OF[$name]:-}" ]; then
        # keep the highest version by version-sorted filename
        ZIP_OF[$name]="$(printf '%s\n%s\n' "${ZIP_OF[$name]}" "$z" | sort -V | tail -n1)"
    else
        ZIP_OF[$name]="$z"
    fi
done

[ "${#ZIP_OF[@]}" -gt 0 ] || die "no readable module manifests found under $FROM_DIR"

for name in "${!ZIP_OF[@]}"; do
    DEPS_OF[$name]="$(deps_of "${ZIP_OF[$name]}" | tr '\n' ' ')" || true
done

# --- topological sort (DFS), dependencies first ---
declare -A STATE=()   # <unset> | temp | done
declare -a ORDER=()
visit() {
    local n="$1" d
    case "${STATE[$n]:-}" in
        done) return 0 ;;
        temp) log "WARNING: dependency cycle involving $n — proceeding anyway"; return 0 ;;
    esac
    STATE[$n]="temp"
    for d in ${DEPS_OF[$n]:-}; do
        [ -n "${ZIP_OF[$d]:-}" ] && visit "$d"   # only order deps we actually have
    done
    STATE[$n]="done"
    ORDER+=("$n")
}
# visit in stable name order for reproducible output
while IFS= read -r name; do visit "$name"; done \
    < <(printf '%s\n' "${!ZIP_OF[@]}" | sort)

log "resolved install order (${#ORDER[@]} modules):"
i=0
for name in "${ORDER[@]}"; do i=$((i+1)); log "  $i. $name -> ${ZIP_OF[$name]}"; done

# --- generate CmsShell script ---
OCSH="$(mktemp /tmp/import-modules-XXXXXX.ocsh)"
{
    echo "login \"$OC_USER\" \"$OC_PASSWORD\""
    echo "setSiteRoot \"$SITE\""
    for name in "${ORDER[@]}"; do
        echo "replaceModule \"${ZIP_OF[$name]}\""
    done
    echo "exit"
} > "$OCSH"

if [ "$RUN" -ne 1 ]; then
    log "DRY RUN (no --run). Generated CmsShell script:"
    sed 's/^/    /' "$OCSH"
    rm -f "$OCSH"
    exit 0
fi

# --- copy zips into the default module package dir (optional) ---
if [ "$COPY_TO_DEFAULT" -eq 1 ]; then
    WEBINF="$BASE"
    if [ -z "$WEBINF" ] && [ -n "$CMSSHELL" ]; then
        WEBINF="$(dirname "$CMSSHELL")"
    fi
    if [ -n "$WEBINF" ] && [ -d "$WEBINF" ]; then
        dest="$WEBINF/packages/modules"
        mkdir -p "$dest"
        for name in "${ORDER[@]}"; do cp -f "${ZIP_OF[$name]}" "$dest/"; done
        log "copied ${#ORDER[@]} zips to $dest"
    else
        log "WARNING: --copy-to-default set but WEB-INF dir not found (pass --base) — skipping copy"
    fi
fi

# --- run CmsShell ---
log "running CmsShell import (${#ORDER[@]} modules)..."
rc=0
if [ -n "$CMSSHELL" ] && [ -f "$CMSSHELL" ]; then
    bash "$CMSSHELL" -script="$OCSH" || rc=$?
else
    bash /root/execute-opencms-shell.sh "$OCSH" || rc=$?
fi
rm -f "$OCSH"

[ "$rc" -eq 0 ] || die "CmsShell exited with code $rc"
log "import complete."
