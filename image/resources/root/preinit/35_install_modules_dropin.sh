#!/bin/bash
# Install OpenCms modules dropped at /opt/opencms-modules/*.zip via CmsShell
# replaceModule.
#
# State tracking (parity with 40_apply_project_config.sh / 41_apply_project_solr.sh):
#   Registry at /container/webapps/.opencms-state/modules-dropin.applied with one
#   tab-separated line per installed module zip:
#     <filename>\t<sha256>\t<iso-timestamp>
#
# Re-install triggers:
#   - Module zip not yet in registry (first install or new zip added)
#   - Source zip hash differs from registry (template was updated)
#
# Manual force re-install:
#   - Delete the registry file to re-install everything on next start
#   - Delete a single line to re-install just that module

MODULES_DIR="/opt/opencms-modules"
STATE_DIR="/container/webapps/.opencms-state"
REGISTRY="${STATE_DIR}/modules-dropin.applied"

if [ ! -d "${MODULES_DIR}" ]; then
    echo "[modules-dropin] no source dir at ${MODULES_DIR} — skipping"
    exit 0
fi

shopt -s nullglob
ZIPS=("${MODULES_DIR}"/*.zip)
shopt -u nullglob

if [ ${#ZIPS[@]} -eq 0 ]; then
    echo "[modules-dropin] no .zip files in ${MODULES_DIR} — skipping"
    exit 0
fi

mkdir -p "${STATE_DIR}"
touch "${REGISTRY}"

PENDING=()
PENDING_HASHES=()
for ZIP in "${ZIPS[@]}"; do
    name=$(basename "${ZIP}")
    src_hash=$(sha256sum "${ZIP}" | awk '{print $1}')
    registered_hash=$(awk -v n="${name}" -F'\t' '$1==n {print $2; exit}' "${REGISTRY}")

    if [ "${src_hash}" = "${registered_hash}" ]; then
        echo "[modules-dropin] ${name} already installed (hash matches) — skipping"
        continue
    fi
    PENDING+=("${ZIP}")
    PENDING_HASHES+=("${src_hash}")
done

if [ ${#PENDING[@]} -eq 0 ]; then
    echo "[modules-dropin] nothing to install"
    exit 0
fi

admin_passwd=$(get_secret ADMIN_PASSWD_FILE ADMIN_PASSWD)
OCSH_TMP=$(mktemp /tmp/install-modules-XXXXX.ocsh)

{
    echo "login \"Admin\" \"${admin_passwd}\""
    echo "setSiteRoot \"/\""
    for ZIP in "${PENDING[@]}"; do
        echo "replaceModule \"${ZIP}\""
    done
    echo "exit"
} > "${OCSH_TMP}"

echo "[modules-dropin] installing pending modules:"
for ZIP in "${PENDING[@]}"; do echo "  ${ZIP}"; done

bash /root/execute-opencms-shell.sh "${OCSH_TMP}"
EXIT_CODE=$?

rm -f "${OCSH_TMP}"

if [ ${EXIT_CODE} -ne 0 ]; then
    echo "[modules-dropin] WARNING: install exited with code ${EXIT_CODE}. Registry NOT updated; see CmsShell output above."
    exit 0
fi

# CmsShell succeeded → record hashes so we skip these zips next boot.
for i in "${!PENDING[@]}"; do
    name=$(basename "${PENDING[$i]}")
    src_hash="${PENDING_HASHES[$i]}"
    awk -v n="${name}" -F'\t' '$1!=n' "${REGISTRY}" > "${REGISTRY}.tmp"
    printf "%s\t%s\t%s\n" "${name}" "${src_hash}" "$(date -Iseconds)" >> "${REGISTRY}.tmp"
    mv "${REGISTRY}.tmp" "${REGISTRY}"
done
