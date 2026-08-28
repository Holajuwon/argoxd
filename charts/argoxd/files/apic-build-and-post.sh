#!/bin/sh
# apic-build-and-post.sh
#
# Builds an APIC product ZIP from the APIC YAML artifacts in WORK_DIR using
# the @apistudio/apim-cli `apic build` command, then publishes it to the
# APIC standalone instance via:
#   1. POST /api/v1/auth-token  → Bearer token
#   2. POST /idig-broker/publish?is_portal_service=true  → multipart ZIP upload
#
# Environment variables (all required):
#   WORK_DIR             – directory containing the APIC YAML files (default: /work)
#   STANDALONE_URL       – base URL of the standalone APIC instance
#   STANDALONE_USERNAME  – admin username
#   STANDALONE_PASSWORD  – admin password

set -e

WORK_DIR="${WORK_DIR:-/work}"
BUILD_DIR="/tmp/apic-build-out"
BUILD_ZIP="${BUILD_DIR}/pet-mcp-build.zip"

echo "[apic-build-and-post] starting"
echo "[apic-build-and-post] WORK_DIR        : ${WORK_DIR}"
echo "[apic-build-and-post] STANDALONE_URL  : ${STANDALONE_URL}"
echo "[apic-build-and-post] STANDALONE_USER : ${STANDALONE_USERNAME}"
echo "[apic-build-and-post] ARGOXD_ENDPOINT : ${ARGOXD_ENDPOINT}"

for var in STANDALONE_URL STANDALONE_USERNAME STANDALONE_PASSWORD; do
  eval "val=\${${var}:-}"
  if [ -z "$val" ]; then
    echo "[apic-build-and-post] ERROR: ${var} env var is required" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Ensure curl is available (node:XX-alpine ships without it)
# ---------------------------------------------------------------------------

if ! command -v curl > /dev/null 2>&1; then
  echo "[apic-build-and-post] installing curl..."
  apk add --no-cache curl 2>&1
fi

# ---------------------------------------------------------------------------
# Install @apistudio/apim-cli if not already present
# ---------------------------------------------------------------------------

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

ZIP_SIZE=$(wc -c < "${BUILD_ZIP}")
echo "[apic-build-and-post] built ZIP: ${BUILD_ZIP} (${ZIP_SIZE} bytes)"

# ---------------------------------------------------------------------------
# Step 1 — Authenticate: POST /api/v1/auth-token → Bearer token
# ---------------------------------------------------------------------------

echo "[apic-build-and-post] authenticating against ${STANDALONE_URL}/api/v1/auth-token"

AUTH_RESPONSE=$(curl -sk \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${STANDALONE_USERNAME}\",\"password\":\"${STANDALONE_PASSWORD}\"}" \
  "${STANDALONE_URL}/api/v1/auth-token")

echo "[apic-build-and-post] auth response: ${AUTH_RESPONSE}"

# Extract token — works with both {"token":"..."} and {"accessToken":"..."}
TOKEN=$(printf '%s' "${AUTH_RESPONSE}" | \
  node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.token||d.accessToken||d.access_token||'');")

if [ -z "${TOKEN}" ]; then
  echo "[apic-build-and-post] ERROR: failed to extract token from auth response" >&2
  exit 1
fi

echo "[apic-build-and-post] token acquired (${#TOKEN} chars)"

# ---------------------------------------------------------------------------
# Step 2 — Publish: POST /idig-broker/publish?is_portal_service=true
# ---------------------------------------------------------------------------

PUBLISH_URL="${STANDALONE_URL}/idig-broker/publish?is_portal_service=true"
ZIP_FILENAME=$(basename "${BUILD_ZIP}")

echo "[apic-build-and-post] publishing to ${PUBLISH_URL}"

HTTP_STATUS=$(curl -sk \
  -o /tmp/publish-response \
  -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Cookie: accesstoken=Bearer ${TOKEN}" \
  -F "project=@${BUILD_ZIP};type=application/zip;filename=${ZIP_FILENAME}" \
  "${PUBLISH_URL}")

RESPONSE_BODY=$(cat /tmp/publish-response 2>/dev/null || echo "(empty)")
echo "[apic-build-and-post] publish status: ${HTTP_STATUS}"
echo "[apic-build-and-post] publish response: ${RESPONSE_BODY}"

if [ -z "${HTTP_STATUS}" ] || [ "${HTTP_STATUS}" -lt 200 ] || [ "${HTTP_STATUS}" -ge 300 ]; then
  echo "[apic-build-and-post] ERROR: publish returned status ${HTTP_STATUS}" >&2
  exit 1
fi

echo "[apic-build-and-post] done ✓"
