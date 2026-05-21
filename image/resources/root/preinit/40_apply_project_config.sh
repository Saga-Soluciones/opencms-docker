#!/bin/bash
# Apply project-specific config overrides from /opt/opencms-project-config/
# to ${OPENCMS_HOME}/WEB-INF/config/.
#
# Contract:
#   - Mount the project's config directory at /opt/opencms-project-config/
#     (read-only is fine). Every regular file inside overrides the matching
#     file in WEB-INF/config/ by basename.
#
# Order:
#   Runs after 20_check_install.sh (CmsAutoSetup completed) and 30_transform
#   (XSLT patches), so custom files override both upstream defaults and XSLT
#   transformations.
#
# State tracking:
#   Single registry file at /container/webapps/.opencms-state/project-config.applied
#   with one tab-separated line per applied config:
#     <filename>\t<sha256>\t<iso-timestamp>
#
# Re-apply triggers:
#   - Filename not yet in registry (first install or new file added)
#   - Source content hash differs from registry (template was updated)
#
# Manual force re-apply:
#   - Delete the registry file to re-apply everything on next start
#   - Delete a single line to re-apply just that one

SRC_DIR="/opt/opencms-project-config"
DST_DIR="${OPENCMS_HOME}/WEB-INF/config"
STATE_DIR="/container/webapps/.opencms-state"
REGISTRY="${STATE_DIR}/project-config.applied"
LEGACY_FLAG_DIR="/container/webapps/project-config-flags"

if [ ! -d "$SRC_DIR" ]; then
    echo "[project-config] no source dir at ${SRC_DIR} — skipping"
    exit 0
fi

mkdir -p "$STATE_DIR"
touch "$REGISTRY"

# One-time migration from legacy per-file flag mechanism
if [ -d "$LEGACY_FLAG_DIR" ] && [ ! -s "$REGISTRY" ]; then
    echo "[project-config] migrating from legacy per-file flags in ${LEGACY_FLAG_DIR}"
    shopt -s nullglob
    for flag_file in "$LEGACY_FLAG_DIR"/*.flag; do
        name=$(basename "$flag_file" .flag)
        src_file="${SRC_DIR}/${name}"
        if [ -f "$src_file" ]; then
            src_hash=$(sha256sum "$src_file" | awk '{print $1}')
            printf "%s\t%s\t%s\n" "$name" "$src_hash" "migrated" >> "$REGISTRY"
            echo "[project-config]   migrated entry for ${name}"
        fi
    done
    shopt -u nullglob
    rm -rf "$LEGACY_FLAG_DIR"
fi

shopt -s nullglob
for src_file in "$SRC_DIR"/*; do
    [ -f "$src_file" ] || continue
    name=$(basename "$src_file")
    dst_file="${DST_DIR}/${name}"
    src_hash=$(sha256sum "$src_file" | awk '{print $1}')
    registered_hash=$(awk -v n="$name" -F'\t' '$1==n {print $2; exit}' "$REGISTRY")

    if [ "$src_hash" = "$registered_hash" ]; then
        echo "[project-config] ${name} already applied (hash matches) — skipping"
        continue
    fi

    if [ ! -f "$dst_file" ]; then
        echo "[project-config] WARNING: target ${dst_file} does not exist — skipping ${name}"
        continue
    fi

    cp "$src_file" "$dst_file"

    awk -v n="$name" -F'\t' '$1!=n' "$REGISTRY" > "${REGISTRY}.tmp"
    printf "%s\t%s\t%s\n" "$name" "$src_hash" "$(date -Iseconds)" >> "${REGISTRY}.tmp"
    mv "${REGISTRY}.tmp" "$REGISTRY"

    if [ -n "$registered_hash" ]; then
        echo "[project-config] ${name} re-applied (source content changed)"
    else
        echo "[project-config] ${name} applied"
    fi
done
