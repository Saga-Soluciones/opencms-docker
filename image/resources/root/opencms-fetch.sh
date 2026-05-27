#!/bin/bash
set -euo pipefail

# Download + verify OpenCms distribution zip at image build time.
# If OPENCMS_SHA256 is set (preferred via versions.yaml), the downloaded zip is
# verified before being unpacked. Empty SHA256 falls back to legacy behaviour
# (download without verification) so downstream forks aren't forced to pin.

ARTIFACTS_FOLDER="${ARTIFACTS_FOLDER:-/artifacts/}"

if [ -s "${ARTIFACTS_FOLDER}opencms.war" ]; then
    echo "Using local WAR file"
    exit 0
fi

if [ ! -d "${ARTIFACTS_FOLDER}" ]; then
    mkdir -v -p "${ARTIFACTS_FOLDER}"
fi

if [ ! -s "${ARTIFACTS_FOLDER}opencms.zip" ]; then
    echo "Downloading OpenCms from '${OPENCMS_URL}'"
    wget -nv "${OPENCMS_URL}" -O "${ARTIFACTS_FOLDER}opencms.zip"
    echo "Download complete"
fi

if [ -n "${OPENCMS_SHA256:-}" ]; then
    echo "Verifying SHA256 of opencms.zip against pinned digest"
    echo "${OPENCMS_SHA256}  ${ARTIFACTS_FOLDER}opencms.zip" | sha256sum -c -
else
    echo "WARNING: OPENCMS_SHA256 not set — skipping integrity verification"
fi

unzip -q "${ARTIFACTS_FOLDER}opencms.zip" opencms.war -d "${ARTIFACTS_FOLDER}"
echo "Unziped WAR file"
rm -fv "${ARTIFACTS_FOLDER}opencms.zip"
ls -la "${ARTIFACTS_FOLDER}"
