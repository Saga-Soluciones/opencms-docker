#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: build.sh <opencms-version>  (e.g. build.sh 21.0.1)}"

if ! command -v yq &>/dev/null || ! command -v jq &>/dev/null; then
    echo "ERROR: yq and jq are required. Install with: brew install yq jq  (or apt/dnf equivalent)"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY=$(yq ".versions[] | select(.opencms == \"$VERSION\")" "$REPO_ROOT/versions.yaml" -o=json)

if [ -z "$ENTRY" ]; then
    echo "ERROR: Version $VERSION not found in versions.yaml"
    echo "Available versions:"
    yq '.versions[].opencms' "$REPO_ROOT/versions.yaml"
    exit 1
fi

BASE_IMAGE=$(echo "$ENTRY" | jq -r .base_image)
OPENCMS_TAG=$(echo "$ENTRY" | jq -r .opencms_tag)
OPENCMS_SHA256=$(echo "$ENTRY" | jq -r '.opencms_sha256 // empty')
IMAGE_DIR=$(echo "$ENTRY" | jq -r '.image_dir // empty')
if [ -z "$IMAGE_DIR" ]; then
    IMAGE_DIR=$(yq '.defaults.image_dir // "image"' "$REPO_ROOT/versions.yaml")
fi
YAML_URL=$(echo "$ENTRY" | jq -r '.opencms_url // empty')
if [ -n "$YAML_URL" ]; then
    OPENCMS_URL="$YAML_URL"
else
    OPENCMS_URL="https://github.com/alkacon/opencms-core/releases/download/${OPENCMS_TAG}/opencms-${VERSION}-distribution.zip"
fi

echo "Building sagasoluciones/opencms-tomcat:${VERSION}-dev"
echo "  Base image  : $BASE_IMAGE"
echo "  OpenCms tag : $OPENCMS_TAG"
echo "  OpenCms URL : $OPENCMS_URL"
echo "  SHA256      : ${OPENCMS_SHA256:-<not pinned>}"
echo "  Context     : $IMAGE_DIR/"

docker build \
    --build-arg SERVLET_CONTAINER=tomcat \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg OPENCMS_URL="$OPENCMS_URL" \
    --build-arg OPENCMS_VERSION="$VERSION" \
    --build-arg OPENCMS_SHA256="$OPENCMS_SHA256" \
    -t "sagasoluciones/opencms-tomcat:${VERSION}-dev" \
    "$REPO_ROOT/$IMAGE_DIR"

echo ""
echo "Done: sagasoluciones/opencms-tomcat:${VERSION}-dev"
echo "Note: -dev tag is local only. To publish, push git tag: ${VERSION}-tomcat"
