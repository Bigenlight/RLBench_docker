#!/bin/bash
# Entrypoint for the BridgeVLA Docker image.
#
# Two responsibilities:
#   1. Start Xvfb on :99 if $DISPLAY is unset (so CoppeliaSim's bundled Qt5
#      has an X server to talk to and can produce real camera frames under
#      the QT_PLUGIN_PATH=${COPPELIASIM_ROOT} fix baked into the image).
#   2. On FIRST container start, install BridgeVLA's vendored libs from the
#      bind-mounted source tree:
#          /workspace/BridgeVLA/finetune/bridgevla/libs/{YARR,peract_colab,point-renderer}
#      followed by BridgeVLA's main package via `pip install -e .`.
#      Guarded by a marker file so subsequent starts skip this step.
#
# If $DISPLAY is already set when launching the container (e.g. host X11
# socket mounted), Xvfb is skipped and the existing display is used.

set -e

# --- 1. Xvfb ----------------------------------------------------------------
if [ -z "${DISPLAY:-}" ]; then
    Xvfb :99 -screen 0 1280x1024x24 +extension GLX +render -noreset \
        > /tmp/xvfb.log 2>&1 &
    # Wait for the X socket to appear before exporting DISPLAY.
    for _ in $(seq 1 20); do
        [ -e /tmp/.X11-unix/X99 ] && break
        sleep 0.5
    done
    if [ ! -e /tmp/.X11-unix/X99 ]; then
        echo "ERROR: Xvfb failed to start. See /tmp/xvfb.log:" >&2
        cat /tmp/xvfb.log >&2
        exit 1
    fi
    export DISPLAY=:99
fi

# --- 2. BridgeVLA bind-mount lib install (first-run only) -------------------
BRIDGEVLA_FINETUNE=/workspace/BridgeVLA/finetune
MARKER=/workspace/.bridgevla_libs_installed

if [ -d "${BRIDGEVLA_FINETUNE}" ] && [ ! -e "${MARKER}" ]; then
    echo "[entrypoint] First-run BridgeVLA libs install from ${BRIDGEVLA_FINETUNE}"
    cd "${BRIDGEVLA_FINETUNE}"
    pip install --no-deps -e bridgevla/libs/YARR
    pip install --no-deps -e bridgevla/libs/peract_colab
    pip install --no-deps -e bridgevla/libs/point-renderer
    # BridgeVLA main package; --no-deps because all setup.py deps are
    # already baked into the image (see bridgevla.Dockerfile).
    pip install --no-deps -e .
    touch "${MARKER}"
    cd /workspace
    echo "[entrypoint] BridgeVLA libs install complete."
fi

exec "$@"
