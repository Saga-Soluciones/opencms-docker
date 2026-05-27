#!/bin/bash
# Apply project-specific Solr config overrides from /opt/opencms-project-solr/
# to ${OPENCMS_HOME}/WEB-INF/solr/.
#
# Contract:
#   - Mount the project's Solr tree at /opt/opencms-project-solr/ (read-only is fine).
#     Every regular file inside overrides the matching file in WEB-INF/solr/ by
#     **relative path** (recursive — full tree mirror, configsets/default/conf/...).
#
# Order:
#   Runs right after 40_apply_project_config.sh so the same one-shot overlay phase
#   covers both WEB-INF/config and WEB-INF/solr.
#
# State tracking:
#   Single registry at /container/webapps/.opencms-state/project-solr.applied with
#   one tab-separated line per applied file:
#     <relative/path>\t<sha256>\t<iso-timestamp>
#
# Re-apply triggers:
#   - Relative path not yet in registry (first install or new file added)
#   - Source content hash differs from registry (template was updated)
#
# Manual force re-apply:
#   - Delete the registry file to re-apply everything on next start
#   - Delete a single line to re-apply just that one path
#
# Notes:
#   - schema.xml / solrconfig.xml / managed-schema changes typically require a
#     Solr core reload or full reindex. Hook emits a WARNING when those files
#     are (re-)applied so operators notice.
#   - Files that have no counterpart in WEB-INF/solr/ ARE copied (Solr accepts
#     additional configset assets such as custom synonyms / stopwords).
#     Parent dirs are created on demand.

SRC_DIR="/opt/opencms-project-solr"
DST_DIR="${OPENCMS_HOME}/WEB-INF/solr"
STATE_DIR="/container/webapps/.opencms-state"
REGISTRY="${STATE_DIR}/project-solr.applied"

if [ ! -d "$SRC_DIR" ]; then
    echo "[project-solr] no source dir at ${SRC_DIR} — skipping"
    exit 0
fi

if [ -z "$(find "$SRC_DIR" -mindepth 1 -type f 2>/dev/null | head -1)" ]; then
    echo "[project-solr] source dir ${SRC_DIR} is empty — skipping"
    exit 0
fi

if [ ! -d "$DST_DIR" ]; then
    echo "[project-solr] WARNING: target dir ${DST_DIR} does not exist — skipping"
    exit 0
fi

mkdir -p "$STATE_DIR"
touch "$REGISTRY"

reindex_warning=0

# Use -print0 + read -d '' for paths with whitespace
while IFS= read -r -d '' src_file; do
    rel_path="${src_file#${SRC_DIR}/}"
    dst_file="${DST_DIR}/${rel_path}"
    src_hash=$(sha256sum "$src_file" | awk '{print $1}')
    registered_hash=$(awk -v n="$rel_path" -F'\t' '$1==n {print $2; exit}' "$REGISTRY")

    if [ "$src_hash" = "$registered_hash" ]; then
        echo "[project-solr] ${rel_path} already applied (hash matches) — skipping"
        continue
    fi

    mkdir -p "$(dirname "$dst_file")"
    cp "$src_file" "$dst_file"

    awk -v n="$rel_path" -F'\t' '$1!=n' "$REGISTRY" > "${REGISTRY}.tmp"
    printf "%s\t%s\t%s\n" "$rel_path" "$src_hash" "$(date -Iseconds)" >> "${REGISTRY}.tmp"
    mv "${REGISTRY}.tmp" "$REGISTRY"

    if [ -n "$registered_hash" ]; then
        echo "[project-solr] ${rel_path} re-applied (source content changed)"
    else
        echo "[project-solr] ${rel_path} applied"
    fi

    case "$(basename "$rel_path")" in
        schema.xml|managed-schema|solrconfig.xml)
            reindex_warning=1
            ;;
    esac
done < <(find "$SRC_DIR" -type f -print0)

if [ "$reindex_warning" = "1" ]; then
    echo "[project-solr] WARNING: schema/solrconfig changed — Solr core reload or full reindex is required for changes to take effect"
fi
