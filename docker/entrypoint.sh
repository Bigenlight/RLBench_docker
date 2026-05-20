#!/bin/bash
# Entrypoint for the RLBench Docker image.
#
# If $DISPLAY is unset, starts Xvfb on :99 and exports DISPLAY=:99, then exec's
# the user command (default: bash). With QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
# baked into the image (see Dockerfile), CoppeliaSim's Qt5 finds its
# xcbglintegrations/ plugins and produces REAL camera frames (not all-zero)
# under the Xvfb software-GLX backend — no VirtualGL required.
#
# If $DISPLAY is already set when launching the container (e.g. host X11
# socket mounted), Xvfb is skipped and the existing display is used.

set -e

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

exec "$@"
