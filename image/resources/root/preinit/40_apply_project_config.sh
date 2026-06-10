#!/bin/bash
# Apply project-specific config overrides from /opt/opencms-project-config/
# to ${OPENCMS_HOME}/WEB-INF/config/.
#
# Contract:
#   - Mount the project's config tree at /opt/opencms-project-config/
#     (read-only is fine). Every regular file inside is copied to the matching
#     **relative path** under WEB-INF/config/ (recursive — full tree mirror,
#     parent dirs created on demand). `.gitkeep` placeholders are excluded.
#   - Copy is unconditional: no registry, no flags, no hash comparison. Files
#     with no counterpart in WEB-INF/config/ are copied too (custom
#     project-only config files are supported).
#
# Order:
#   Runs after 20_check_install.sh (CmsAutoSetup completed) and 30_transform
#   (XSLT patches), so custom files override both upstream defaults and XSLT
#   transformations.
#
# Side effect (by design):
#   Because every preinit run re-copies the overrides, the project tree is the
#   source of truth — runtime edits to a destination file (e.g. via the
#   Workplace) are overwritten by the project version on the next container
#   (re)create.

SRC_DIR="/opt/opencms-project-config"
DST_DIR="${OPENCMS_HOME}/WEB-INF/config"

if [ ! -d "$SRC_DIR" ]; then
    echo "[project-config] no source dir at ${SRC_DIR} — skipping"
    exit 0
fi

if [ -z "$(find "$SRC_DIR" -type f ! -name .gitkeep 2>/dev/null | head -1)" ]; then
    echo "[project-config] no files to copy in ${SRC_DIR} — skipping"
    exit 0
fi

echo "[project-config] applying overrides from ${SRC_DIR}"

copied=0

# Use -print0 + read -d '' for paths with whitespace
while IFS= read -r -d '' src_file; do
    rel_path="${src_file#"$SRC_DIR"/}"
    dst_file="${DST_DIR}/${rel_path}"

    if [ -f "$dst_file" ]; then
        status="override"
    else
        status="new"
    fi

    mkdir -p "$(dirname "$dst_file")"
    cp "$src_file" "$dst_file"
    copied=$((copied + 1))

    echo "[project-config] ${rel_path} (${status})"
done < <(find "$SRC_DIR" -type f ! -name .gitkeep -print0)

echo "[project-config] done — ${copied} file(s) copied"
