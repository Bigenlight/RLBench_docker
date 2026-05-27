#!/usr/bin/env bash
# =============================================================================
# test_patch_apply.sh
# =============================================================================
# Applies bypass_demo_loading.patch inside the container and verifies the
# resulting file is syntactically valid Python.
#
# Two ways to get the patch file inside the container:
#   (A) Mount the RLBench_docker repo into the container, e.g.
#         -v /host/path/to/RLBench_docker:/workspace/RLBench_docker
#       then the patch lives at:
#         /workspace/RLBench_docker/docker/patches/bypass_demo_loading.patch
#   (B) Copy the patch into the container at build time (COPY in Dockerfile)
#       or at runtime (`docker cp`), e.g. to /tmp/bypass_demo_loading.patch
#
# Override the patch path by setting PATCH_FILE before invoking this script.
# =============================================================================
set -euo pipefail

PATCH_FILE="${PATCH_FILE:-/workspace/RLBench_docker/docker/patches/bypass_demo_loading.patch}"
TARGET_DIR="${TARGET_DIR:-/workspace/BridgeVLA/finetune}"
TARGET_FILE="RLBench/utils/custom_rlbench_env.py"

if [ ! -f "${PATCH_FILE}" ]; then
    echo "ERROR: patch file not found at ${PATCH_FILE}" >&2
    echo "Set PATCH_FILE=/path/to/bypass_demo_loading.patch and retry." >&2
    exit 1
fi

if [ ! -d "${TARGET_DIR}" ]; then
    echo "ERROR: target dir not found at ${TARGET_DIR}" >&2
    exit 1
fi

cd "${TARGET_DIR}"

# Idempotency: if patch already applied, skip silently.
if patch -p1 --dry-run --reverse --silent < "${PATCH_FILE}" >/dev/null 2>&1; then
    echo "Patch already applied to ${TARGET_FILE} - skipping."
else
    echo "Applying ${PATCH_FILE} to ${TARGET_DIR} ..."
    patch -p1 < "${PATCH_FILE}"
fi

# Syntax check
python -c "import ast; ast.parse(open('${TARGET_FILE}').read())"

echo "Patch applied successfully"
