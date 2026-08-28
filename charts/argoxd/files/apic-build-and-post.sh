#!/bin/sh
# apic-build-and-post.sh
#
# Builds an APIC product ZIP from the APIC YAML artifacts in WORK_DIR using
# the @apistudio/apim-cli `apic build` command, then POSTs the resulting ZIP
# (base64-encoded) to UPLOAD_URL.
#
# Environment variables:
#   WORK_DIR    – directory containing the APIC YAML files (default: /work)
#   UPLOAD_URL  – HTTP endpoint to POST the packaged ZIP to (required)

set -e

WORK_DIR="${WORK_DIR:-/work}"
BUILD_DIR="/tmp/apic-build-out"
BUILD_ZIP="${BUILD_DIR}/pet-mcp-build.zip"

echo "[apic-build-and-post] starting"
echo "[apic-build-and-post] WORK_DIR   : ${WORK_DIR}"
echo "[apic-build-and-post] UPLOAD_URL : ${UPLOAD_URL}"

if [ -z "${UPLOAD_URL}" ]; then
  echo "[apic-build-and-post] ERROR: UPLOAD_URL env var is required" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Install @apistudio/apim-cli if not already present
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Ensure curl is available (node:XX-alpine ships without it)
# ---------------------------------------------------------------------------

if ! command -v curl > /dev/null 2>&1; then
  echo "[apic-build-and-post] installing curl..."
  apk add --no-cache curl 2>&1
fi

if ! command -v apic > /dev/null 2>&1; then
  echo "[apic-build-and-post] installing @apistudio/apim-cli..."
  npm install -g --prefer-offline --no-audit --no-fund @apistudio/apim-cli 2>&1
  echo "[apic-build-and-post] @apistudio/apim-cli installed: $(apic --version)"
else
  echo "[apic-build-and-post] apic already available: $(apic --version)"
fi

# ---------------------------------------------------------------------------
# Copy work files to a writable temp dir (ConfigMap mounts are read-only
# symlink trees; apic build requires a real, resolvable directory)
# ---------------------------------------------------------------------------

APIC_DIR="/tmp/apic-workdir"
APIC_PROJECT_DIR="${APIC_DIR}/pet-mcp"
mkdir -p "${APIC_PROJECT_DIR}"

# .apistudio-projects lives at the root of --localDir
cp -L "${WORK_DIR}/.apistudio-projects" "${APIC_DIR}/.apistudio-projects"

# all YAML files go inside the project subdirectory
for f in "${WORK_DIR}"/*.yaml "${WORK_DIR}"/*.yml; do
  [ -f "$f" ] && cp -L "$f" "${APIC_PROJECT_DIR}/"
done

echo "[apic-build-and-post] localDir layout:"
ls -la "${APIC_DIR}"
echo "[apic-build-and-post] project dir:"
ls -la "${APIC_PROJECT_DIR}"

# ---------------------------------------------------------------------------
# Run `apic build` against the real copy
# ---------------------------------------------------------------------------

mkdir -p "${BUILD_DIR}"
echo "[apic-build-and-post] running: apic build pet-mcp --localDir ${APIC_DIR} --output ${BUILD_ZIP}"

apic build pet-mcp \
  --localDir "${APIC_DIR}" \
  --output   "${BUILD_ZIP}"

# ---------------------------------------------------------------------------
# Locate the produced ZIP
# ---------------------------------------------------------------------------

ZIP_FILE="${BUILD_ZIP}"

if [ -z "${ZIP_FILE}" ]; then
  echo "[apic-build-and-post] ERROR: apic build produced no ZIP in ${BUILD_DIR}" >&2
  ls -la "${BUILD_DIR}" >&2
  exit 1
fi

ZIP_SIZE=$(wc -c < "${ZIP_FILE}")
echo "[apic-build-and-post] built ZIP  : ${ZIP_FILE} (${ZIP_SIZE} bytes)"

# ---------------------------------------------------------------------------
# Base64-encode and POST to backend
# ---------------------------------------------------------------------------

ZIP_B64=$(base64 < "${ZIP_FILE}" | tr -d '\n')
echo "[apic-build-and-post] base64 size: ${#ZIP_B64} chars"

PAYLOAD="{\"zipBase64\":\"${ZIP_B64}\"}"

echo "[apic-build-and-post] posting to ${UPLOAD_URL}"
echo "[apic-build-and-post] payload size: ${#PAYLOAD} bytes"

HTTP_STATUS=$(printf '%s' "${PAYLOAD}" | \
  curl -s -o /tmp/apic-post-response -w "%{http_code}" \
       -X POST \
       -H "Content-Type: application/json" \
       -d @- \
       "${UPLOAD_URL}")

RESPONSE_BODY=$(cat /tmp/apic-post-response 2>/dev/null || echo "(empty)")
echo "[apic-build-and-post] response status: ${HTTP_STATUS}"
echo "[apic-build-and-post] response body  : ${RESPONSE_BODY}"

if [ -z "${HTTP_STATUS}" ] || [ "${HTTP_STATUS}" -lt 200 ] || [ "${HTTP_STATUS}" -ge 300 ]; then
  echo "[apic-build-and-post] ERROR: server returned status ${HTTP_STATUS}" >&2
  exit 1
fi

echo "[apic-build-and-post] done ✓"
