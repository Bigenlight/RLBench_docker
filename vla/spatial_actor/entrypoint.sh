#!/bin/bash
# Entrypoint for the SpatialActor Docker image.
#
# Two responsibilities (same shape as vla/bridgevla/entrypoint.sh):
#   1. Start Xvfb on :99 if $DISPLAY is unset, so CoppeliaSim's bundled Qt5 has
#      an X server to talk to and produces real camera frames under the
#      QT_PLUGIN_PATH=${COPPELIASIM_ROOT} fix baked into the image (see
#      docker/README.md §"Why QT_PLUGIN_PATH").
#   2. On FIRST container start, install the two bind-mounted, in-repo libs from
#      the SpatialActor source tree mounted at /workspace/SpatialActor:
#          - third_libs/point-renderer   (custom CUDA op, compiled with nvcc)
#          - .                           (the `spatial_actor` package itself)
#      Both with --no-deps because every runtime dependency is already baked
#      into the image (see Dockerfile). PyRep / RLBench / YARR are NOT installed
#      here — they are cloned + pinned + installed at build time.
#      Guarded by a marker file so subsequent starts in the SAME container skip
#      it. The marker lives in the (ephemeral) image /workspace, NOT in the
#      bind-mount, on purpose: `pip install -e` registers an egg-link into the
#      container's site-packages, which is recreated on every `--rm` run, so the
#      install must re-run per fresh container. The compiled point-renderer .so
#      persists in the host bind-mount, so nvcc does NOT recompile — re-install
#      is just a fast egg-link re-registration (~10-20 s).
#
# If $DISPLAY is already set when launching the container, Xvfb is skipped and
# the existing display is used.

set -e

# --- 1. Xvfb ----------------------------------------------------------------
# Start Xvfb on :99 unless a genuine external display is in use. The image bakes
# DISPLAY=:99 as a default, so gating only on "DISPLAY unset" would skip Xvfb on
# a plain `docker run` (no `-e DISPLAY=`) and leave CoppeliaSim with no X server.
# So we also start Xvfb when DISPLAY is the bare :99 default and nothing is yet
# listening on /tmp/.X11-unix/X99 — making eval work with OR without `-e DISPLAY=`.
if [ -z "${DISPLAY:-}" ] || { [ "${DISPLAY}" = ":99" ] && [ ! -e /tmp/.X11-unix/X99 ]; }; then
    Xvfb :99 -screen 0 1280x1024x24 +extension GLX +render -noreset \
        > /tmp/xvfb.log 2>&1 &
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

# --- 2. SpatialActor bind-mount lib install (first-run only) ----------------
SA=/workspace/SpatialActor
MARKER=/workspace/.spatial_actor_installed

if [ -d "${SA}" ] && [ ! -e "${MARKER}" ]; then
    echo "[entrypoint] First-run install of bind-mounted SpatialActor libs from ${SA}"
    cd "${SA}"
    # Custom CUDA point renderer — compiled against the baked torch 1.12.1+cu113
    # and the CUDA 11.3 toolkit in the image. FORCE_CUDA mirrors the upstream
    # setup.py guard for headless (no GPU visible at build) compilation.
    # --no-build-isolation: point-renderer's setup.py imports torch at build
    # time, which only exists in the baked env (an isolated build env would not
    # have it). --no-deps: its runtime deps are all baked into the image.
    FORCE_CUDA=1 pip install --no-deps --no-build-isolation -e third_libs/point-renderer
    # The spatial_actor package itself; --no-deps because all of setup.py's deps
    # are baked into the image (and its triton==2.0.0 / tensorflow pins, which
    # conflict with torch 1.12.1 and are never imported, are deliberately
    # skipped — see Dockerfile and README §"What this setup solves").
    pip install --no-deps --no-build-isolation -e .
    touch "${MARKER}"
    cd /workspace
    echo "[entrypoint] SpatialActor libs install complete."
fi

exec "$@"
