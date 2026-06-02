#!/bin/bash
# Entrypoint for the TGM-VLA Docker image.
#
# Three responsibilities:
#   1. Start Xvfb on :99 if $DISPLAY is unset (so CoppeliaSim's bundled Qt5
#      has an X server to talk to and can produce real camera frames under
#      the QT_PLUGIN_PATH=${COPPELIASIM_ROOT} fix baked into the image).
#   2. Symlink the baked-in SAM2 checkpoint into TGM-VLA's expected path
#      (tgm_vla/network/sam2_train/checkpoints/) on first start.
#   3. On FIRST container start, install TGM-VLA's vendored libs from the
#      bind-mounted source tree:
#          /workspace/TGM-VLA/tgm_vla/libs/{RLBench,robot-colosseum,YARR,
#                                            peract_colab,PyRep,point-renderer}
#      followed by TGM-VLA's main package via `pip install -e .`. point-renderer
#      compiles a custom CUDA extension at install time. Guarded by a marker
#      file so subsequent starts skip this step.
#
# If $DISPLAY is already set when launching the container (e.g. host X11
# socket mounted), Xvfb is skipped and the existing display is used.

set -e

# --- 1. Xvfb ----------------------------------------------------------------
# Use the X server pointed at by $DISPLAY if its socket exists (host X11
# mounted, or another Xvfb already running). Otherwise start our own Xvfb on
# :99. (The Dockerfile's `ENV DISPLAY=:99` would otherwise short-circuit the
# old "is DISPLAY empty?" check before Xvfb ever started.)
need_xvfb=1
if [ -n "${DISPLAY:-}" ]; then
    dpy_num="${DISPLAY#:}"
    dpy_num="${dpy_num%%.*}"
    if [ -e "/tmp/.X11-unix/X${dpy_num}" ]; then
        need_xvfb=0
    fi
fi
if [ "$need_xvfb" = "1" ]; then
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

# XDG_RUNTIME_DIR — Qt complains noisily without this.
mkdir -p "${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
chmod 700 "${XDG_RUNTIME_DIR:-/tmp/runtime-root}"

# --- 2. TGM-VLA bind-mount lib install (first-run only) ---------------------
TGMVLA_ROOT=/workspace/TGM-VLA
# Detect "already installed" by trying to import the vendored libs in this
# image's venv. A bind-mount file marker would falsely claim "installed" after
# an image rebuild (new venv, but old source tree still has the marker file).
SAM2_CKPT_TARGET="${TGMVLA_ROOT}/tgm_vla/network/sam2_train/checkpoints/sam2.1_hiera_base_plus.pt"
PATCH_DIR=/opt/tgmvla_patches

need_install=1
if python -c "import rlbench, pyrep, point_renderer, tgm_vla" 2>/dev/null; then
    need_install=0
fi

if [ -d "${TGMVLA_ROOT}" ] && [ "${need_install}" = "1" ]; then
    echo "[entrypoint] Installing TGM-VLA vendored libs from ${TGMVLA_ROOT}"
    cd "${TGMVLA_ROOT}"

    # Apply patches idempotently. -N skips already-applied hunks, so re-runs
    # are safe even if the bind-mount source already has the patch.
    if [ -d "${PATCH_DIR}" ]; then
        for p in "${PATCH_DIR}"/*.patch; do
            [ -f "$p" ] || continue
            echo "[entrypoint] Applying patch: $(basename "$p")"
            patch -p1 -N --silent -i "$p" || true
        done
    fi

    # Install order matters: pure-python libs first, then PyRep + point-renderer
    # which need torch already importable (and --no-build-isolation so the
    # already-installed torch + cffi are visible during setup.py).
    pip install --no-deps -e tgm_vla/libs/RLBench
    pip install --no-deps -e tgm_vla/libs/robot-colosseum
    pip install --no-deps -e tgm_vla/libs/YARR
    pip install --no-deps -e tgm_vla/libs/peract_colab
    pip install --no-deps --no-build-isolation -e tgm_vla/libs/PyRep
    pip install --no-deps --no-build-isolation -e tgm_vla/libs/point-renderer
    # TGM-VLA main package; --no-deps because all setup.py deps are already
    # baked into the image (see vla/tgm_vla/Dockerfile).
    pip install --no-deps -e .

    # YARR's setup.py drops opencv-python (non-headless) which fights Qt under
    # Xvfb. Strip both opencv-python and opencv-contrib-python in case future
    # deps drag in either flavour, then keep the headless build that's baked
    # into the image.
    pip uninstall -y opencv-python opencv-contrib-python 2>/dev/null || true

    # SAM2 checkpoint — symlink the baked-in /opt/sam2_ckpts copy into the
    # path TGM-VLA expects, if the user hasn't downloaded their own.
    if [ -f /opt/sam2_ckpts/sam2.1_hiera_base_plus.pt ] && \
       [ ! -e "${SAM2_CKPT_TARGET}" ]; then
        mkdir -p "$(dirname "${SAM2_CKPT_TARGET}")"
        ln -sf /opt/sam2_ckpts/sam2.1_hiera_base_plus.pt "${SAM2_CKPT_TARGET}"
        echo "[entrypoint] Linked baked SAM2 checkpoint -> ${SAM2_CKPT_TARGET}"
    fi

    cd /workspace
    echo "[entrypoint] TGM-VLA libs install complete."
fi

exec "$@"
