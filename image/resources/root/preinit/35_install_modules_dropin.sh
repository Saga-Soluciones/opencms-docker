#!/bin/bash
# Install OpenCms modules ONCE on first boot after install, via import-modules.sh
# (dependency-ordered CmsShell replaceModule + copy into the default module store).
#
# Ordering: this runs in preinit AFTER 20_check_install.sh, so OpenCms is already
# installed and cmsshell.sh exists, while Tomcat is still DOWN — the safe window for
# a standalone CmsShell import (no second live OpenCms competing for the Solr index
# or RFS). Importing here means modules are present on the very FIRST boot.
#
# Source directory resolution (first match wins):
#   1. $MODULES_IMPORT_DIR                          (explicit override)
#   2. /opt/opencms-git/$REPO_NAME/$MODULES_SUBPATH (SAGA repo bind-mount convention)
#   3. /opt/opencms-modules                         (flat drop-in default)
# Zips are discovered recursively, so per-module gradle */build/*.zip layouts work.
#
# Once-only gate: marker at /container/webapps/.opencms-state/modules-imported.flag.
# Present -> skip. The marker lives in the webapps bind-mount next to
# installed-version, so wiping that mount re-runs the import on the next install.

STATE_DIR="/container/webapps/.opencms-state"
IMPORT_MARKER="${STATE_DIR}/modules-imported.flag"
CMSSHELL="${OPENCMS_HOME}/WEB-INF/cmsshell.sh"

# --- resolve module source dir ---
if [ -n "${MODULES_IMPORT_DIR:-}" ]; then
    MODULES_DIR="${MODULES_IMPORT_DIR}"
elif [ -n "${REPO_NAME:-}" ]; then
    MODULES_DIR="/opt/opencms-git/${REPO_NAME}/${MODULES_SUBPATH:-modules}"
else
    MODULES_DIR="/opt/opencms-modules"
fi

# --- once-only gate ---
if [ -f "${IMPORT_MARKER}" ]; then
    echo "[modules-dropin] already imported (marker present) — skipping"
    exit 0
fi

# --- toggle: opt out of the first-boot auto-import ---
# Default on. When disabled we skip WITHOUT setting the marker, so the import stays
# PENDING — flip MODULES_IMPORT_ENABLED=true and restart and it imports then.
MODULES_IMPORT_ENABLED="${MODULES_IMPORT_ENABLED:-true}"
case "${MODULES_IMPORT_ENABLED,,}" in
    false|0|no|off)
        echo "[modules-dropin] auto-import disabled (MODULES_IMPORT_ENABLED=${MODULES_IMPORT_ENABLED}) — skipping (left pending)"
        exit 0
        ;;
esac

# --- OpenCms must be installed (cmsshell.sh is created by 20_check_install) ---
if [ ! -f "${CMSSHELL}" ]; then
    echo "[modules-dropin] OpenCms not installed yet (no ${CMSSHELL}) — skipping"
    exit 0
fi

# --- source dir + zips present? ---
if [ ! -d "${MODULES_DIR}" ]; then
    echo "[modules-dropin] no module source dir at ${MODULES_DIR} — skipping"
    exit 0
fi

zip_count=$(find "${MODULES_DIR}" -type f -name '*.zip' 2>/dev/null | wc -l)
if [ "${zip_count}" -eq 0 ]; then
    echo "[modules-dropin] no .zip files under ${MODULES_DIR} — skipping"
    exit 0
fi

admin_passwd=$(get_secret ADMIN_PASSWD_FILE ADMIN_PASSWD)

echo "[modules-dropin] importing ${zip_count} module zip(s) from ${MODULES_DIR} (dependency-ordered, copy-to-default)"
chmod +x "${CMSSHELL}" 2>/dev/null || true

if /root/import-modules.sh \
        --from-dir "${MODULES_DIR}" --recursive \
        --cmsshell "${CMSSHELL}" \
        --user Admin --password "${admin_passwd}" \
        --site / --copy-to-default --run; then
    mkdir -p "${STATE_DIR}"
    touch "${IMPORT_MARKER}"
    echo "[modules-dropin] import complete — marker set at ${IMPORT_MARKER}"
else
    echo "[modules-dropin] WARNING: import failed — marker NOT set; will retry next boot. See CmsShell output above."
fi

exit 0
