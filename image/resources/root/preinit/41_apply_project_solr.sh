#!/bin/bash
# Apply project-specific Solr config overrides from /opt/opencms-project-solr/
# to ${OPENCMS_HOME}/WEB-INF/solr/.
#
# Contract:
#   - Mount the project's Solr tree at /opt/opencms-project-solr/ (read-only is
#     fine). Every regular file inside is copied to the matching **relative
#     path** under WEB-INF/solr/ (recursive — full tree mirror,
#     configsets/default/conf/..., parent dirs created on demand). `.gitkeep`
#     placeholders are excluded.
#   - Copy is unconditional: no registry, no flags, no hash comparison. Files
#     with no counterpart in WEB-INF/solr/ are copied too (Solr accepts
#     additional configset assets such as custom synonyms / stopwords).
#
# Order:
#   Runs right after 40_apply_project_config.sh so the same overlay phase
#   covers both WEB-INF/config and WEB-INF/solr.
#
# Side effect (by design):
#   Because every preinit run re-copies the overrides, the project tree is the
#   source of truth — runtime edits to a destination file are overwritten by
#   the project version on the next container (re)create.
#
# Notes:
#   - schema.xml / solrconfig.xml / managed-schema changes typically require a
#     Solr core reload or full reindex. A WARNING is emitted when those files
#     are copied so operators notice.

SRC_DIR="/opt/opencms-project-solr"
DST_DIR="${OPENCMS_HOME}/WEB-INF/solr"

if [ ! -d "$SRC_DIR" ]; then
    echo "[project-solr] no source dir at ${SRC_DIR} — skipping"
    exit 0
fi

if [ -z "$(find "$SRC_DIR" -type f ! -name .gitkeep 2>/dev/null | head -1)" ]; then
    echo "[project-solr] no files to copy in ${SRC_DIR} — skipping"
    exit 0
fi

echo "[project-solr] applying overrides from ${SRC_DIR}"

copied=0
reindex_warning=0

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

    echo "[project-solr] ${rel_path} (${status})"

    case "$(basename "$rel_path")" in
        schema.xml|managed-schema|solrconfig.xml)
            reindex_warning=1
            ;;
    esac
done < <(find "$SRC_DIR" -type f ! -name .gitkeep -print0)

echo "[project-solr] done — ${copied} file(s) copied"

if [ "$reindex_warning" = "1" ]; then
    echo "[project-solr] WARNING: schema/solrconfig changed — Solr core reload or full reindex is required for changes to take effect"
fi
