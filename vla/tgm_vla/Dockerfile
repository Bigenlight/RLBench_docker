# TGM-VLA Docker — RLBench + TGM-VLA eval stack.
#
# Builds an image that combines a working headless RLBench setup (per
# docker/Dockerfile + vla/bridgevla/Dockerfile) with the TGM-VLA
# (https://github.com/PuFanqi23/TGM-VLA) eval dependencies (PyTorch 2.1.0 +
# CUDA 12.1, pytorch3d, transformers, SAM2, CLIP, point-renderer custom CUDA op).
#
# Stack:
#   nvidia/cuda:12.1.1-runtime-ubuntu22.04   (CUDA base, glibc 2.35)
#     + Ubuntu 22.04's Python 3.10            (TGM-VLA env spec)
#     + CoppeliaSim 4.1.0 Edu Ubuntu20.04     (PyRep/RLBench pin this version)
#     + PyTorch 2.1.0 + pytorch3d 0.7.5 wheel
#     + TGM-VLA's pip deps (transformers 4.49.0, hydra-core, bitsandbytes 0.38.1, ...)
#     + SAM2 hiera_base_plus checkpoint (~309 MB, baked in)
#     + Xvfb + tini for the headless entrypoint
#
# TGM-VLA itself + its vendored libs (PyRep, RLBench fork, YARR, peract_colab,
# robot-colosseum, point-renderer, peract) are NOT cloned into the image — they
# are bind-mounted from the host at /workspace/TGM-VLA so the user can edit
# code on the host. The entrypoint runs `pip install -e` on each vendored lib
# plus the main `tgm_vla` package on first container start (this also compiles
# point-renderer's CUDA extension).
#
# Critical Qt plugin discovery fix (same as docker/Dockerfile):
#   ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
# Without this, CoppeliaSim's bundled Qt5 silently returns all-zero camera
# frames under Xvfb. See docker/README.md §"Why QT_PLUGIN_PATH".
#
# Build  (run from repo root):
#   docker build -t tgmvla:latest --build-arg ACCEPT_TGMVLA_LICENCE=YES \
#       -f vla/tgm_vla/Dockerfile .
#
# Run interactively (mount TGM-VLA source + HF cache):
#   docker run --rm -it --gpus all \
#       -v ~/TGM-VLA:/workspace/TGM-VLA \
#       -v ~/.cache/huggingface:/workspace/hf_cache \
#       tgmvla:latest
#
# Expected final image size: ~20 GB on disk uncompressed (CUDA runtime+dev,
# PyTorch + pytorch3d, CoppeliaSim 4.1.0 Edu binaries, SAM2 ckpt).

ARG CUDA_BASE=nvidia/cuda:12.1.1-runtime-ubuntu22.04
FROM ${CUDA_BASE}

# --------------------------------------------------------------------------- #
# License gate — CoppeliaSim Edu, RLBench (PerAct fork), and TGM-VLA are all
# non-redistribution / academic-only; image must NOT be pushed to a public
# registry. Same posture as docker/Dockerfile and vla/bridgevla/Dockerfile.
# --------------------------------------------------------------------------- #
ARG ACCEPT_TGMVLA_LICENCE=
RUN if [ "$ACCEPT_TGMVLA_LICENCE" != "YES" ]; then \
        echo ""; \
        echo "============================================================"; \
        echo "Building tgmvla image requires accepting three licences:"; \
        echo "  1. RLBench (Imperial College London) — academic / non-commercial"; \
        echo "     https://github.com/stepjam/RLBench/blob/master/LICENSE"; \
        echo "  2. CoppeliaSim Edu — educational entities, non-commercial"; \
        echo "     https://manual.coppeliarobotics.com/en/licensing.htm"; \
        echo "  3. TGM-VLA — see upstream repo LICENSE"; \
        echo ""; \
        echo "Read the licences above, then re-run with:"; \
        echo "  docker build --build-arg ACCEPT_TGMVLA_LICENCE=YES ..."; \
        echo "============================================================"; \
        exit 1; \
    fi

ENV DEBIAN_FRONTEND=noninteractive

ARG PYTHON_VERSION=3.10

# --------------------------------------------------------------------------- #
# System deps:
#   - Ubuntu 22.04 ships Python 3.10 natively, so no PPA needed.
#   - git-lfs is required to fetch RLBench fork's .ttt/.ttm scene files
#     (they live in TGM-VLA's vendored libs/ tree).
#   - GL / EGL / X11 / Xvfb for CoppeliaSim's bundled-Qt + headless rendering.
#   - extra xcb libs + ffmpeg for video I/O (pyrender, opencv).
#   - tini PID-1 to reap CoppeliaSim child processes.
# Qt libraries are NOT installed system-wide — CoppeliaSim ships its own under
# $COPPELIASIM_ROOT/{lib,platforms}.
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils \
        build-essential cmake git git-lfs patch unzip pkg-config \
        xvfb libfontconfig1 tini ffmpeg \
        libffi-dev \
        libegl1 libegl1-mesa-dev libgl1 libgl1-mesa-glx libgles2 \
        libglib2.0-0 libsm6 libxext6 libxrender1 \
        libxcb-xinerama0 libxkbcommon-x11-0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 libxkbcommon0 \
        libxcb-cursor0 libxcb-xinput0 libx11-xcb1 libxcb1 \
        libxcb-render0 libxcb-shm0 libxcb-util1 libxcb-glx0 \
        libdbus-1-3 && \
    git lfs install --system && \
    rm -rf /var/lib/apt/lists/*

# Python 3.10 venv is the ONLY python on PATH. setuptools is pinned <81 in
# the SAME RUN so a fresh pip upgrade can't pull a newer setuptools that
# breaks point-renderer's `from pkg_resources import packaging` import.
RUN python${PYTHON_VERSION} -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip wheel "setuptools<81"
ENV PATH=/opt/venv/bin:${PATH}

# --------------------------------------------------------------------------- #
# CoppeliaSim 4.1.0 Edu — exact version (newer = PyRep segfault).
# Same setup as docker/Dockerfile; see that file for the rationale on the
# bundled-Qt + xcbglintegrations/ headless rendering path.
# --------------------------------------------------------------------------- #
ENV COPPELIASIM_ROOT=/opt/coppeliasim
RUN mkdir -p ${COPPELIASIM_ROOT} && \
    wget -qO /tmp/cs.tar.xz \
        https://downloads.coppeliarobotics.com/V4_1_0/CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz && \
    tar -xf /tmp/cs.tar.xz -C ${COPPELIASIM_ROOT} --strip-components=1 && \
    rm /tmp/cs.tar.xz && \
    # PyRep's cffi_build/cffi_build.py creates `libcoppeliaSim.so.1 ->
    # libcoppeliaSim.so` at `pip install -e` time. With `--user $UID:$GID` that
    # write into root-owned $COPPELIASIM_ROOT fails. Pre-create the symlink here
    # so the install step is a no-op.
    ln -sf libcoppeliaSim.so ${COPPELIASIM_ROOT}/libcoppeliaSim.so.1

# --------------------------------------------------------------------------- #
# CRITICAL Qt plugin discovery fix (see docker/README.md for full writeup).
# QT_PLUGIN_PATH=$COPPELIASIM_ROOT lets the bundled Qt find xcbglintegrations/
# → vision sensors produce real frames instead of all-zero blacks.
# --------------------------------------------------------------------------- #
ENV LD_LIBRARY_PATH=${COPPELIASIM_ROOT}:${LD_LIBRARY_PATH} \
    QT_QPA_PLATFORM_PLUGIN_PATH=${COPPELIASIM_ROOT}/platforms \
    QT_PLUGIN_PATH=${COPPELIASIM_ROOT}

# --------------------------------------------------------------------------- #
# CUDA dev headers / nvcc — required at first container start to compile
# TGM-VLA's `point-renderer` extension (custom CUDA op, no prebuilt wheel).
# Placed before the heavy pip install so the layer cache survives torch
# rebuilds.
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-nvcc-12-1 cuda-cudart-dev-12-1 cuda-libraries-dev-12-1 && \
    rm -rf /var/lib/apt/lists/*
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH}

# --------------------------------------------------------------------------- #
# Pip install sequence — ORDER MATTERS.
# Splitting into per-concern RUN layers so a single failure doesn't invalidate
# the whole pip cache layer when debugging the dependency graph.
# --------------------------------------------------------------------------- #

# Build tooling. (setuptools<81 already pinned in the venv-create RUN above.)
RUN pip install --no-cache-dir wheel ninja pyyaml cffi

# torch 2.1.0 + torchvision 0.16.0 (cu121 wheels). TGM-VLA's README pins these.
RUN pip install --no-cache-dir torch==2.1.0 torchvision==0.16.0 \
        --index-url https://download.pytorch.org/whl/cu121

# pytorch3d prerequisites + the cu121/pyt210/py310 prebuilt wheel.
RUN pip install --no-cache-dir fvcore iopath && \
    pip install --no-cache-dir pytorch3d \
        -f https://dl.fbaipublicfiles.com/pytorch3d/packaging/wheels/py310_cu121_pyt210/download.html

# numpy MUST be <2 — torch 2.1.0 was compiled against NumPy 1.x ABI and
# segfaults with the recent numpy>=2 ABI. TGM-VLA's setup.py also pins
# numpy==1.26.4. We pin here before installing TGM-VLA's pip deps so YARR's
# transitive numpy=2 pull-up is overridden cleanly later in the entrypoint.
RUN pip install --no-cache-dir numpy==1.26.4

# opencv-python-headless. The non-headless build (`opencv-python`) and Qt
# fight under Xvfb — TGM-VLA's README explicitly calls this out. YARR's
# setup.py pulls in the non-headless build, which the entrypoint then
# uninstalls and re-installs with the headless variant.
RUN pip install --no-cache-dir opencv-python-headless==4.11.0.86

# TGM-VLA's heavy pip deps from its setup.py — installed at build time so the
# first container start is fast (`pip install -e .` at runtime can then run
# with --no-deps to avoid touching these).
RUN pip install --no-cache-dir \
        transformers==4.49.0 \
        hydra-core==1.3.2 \
        bitsandbytes==0.38.1 \
        einops omegaconf pyrender wandb \
        natsort pyquaternion transforms3d \
        scipy pandas matplotlib \
        absl-py tensorboard \
        moviepy ffmpeg-python \
        plotly dash \
        open3d
# CLIP from openai's git (no pypi release; TGM-VLA's setup.py uses this URL).
RUN pip install --no-cache-dir git+https://github.com/openai/CLIP.git

# Re-pin numpy after the deps block in case any transitive bump leaked through.
RUN pip install --no-cache-dir numpy==1.26.4

# --------------------------------------------------------------------------- #
# SAM2 image-encoder checkpoint (~309 MB). TGM-VLA loads
# `sam2.1_hiera_base_plus.pt` from a relative path inside the source tree.
# Baking it into the image avoids a 5 MB/s Meta-CDN download on every fresh
# container, and lets the entrypoint just symlink it into place at first run.
# --------------------------------------------------------------------------- #
RUN mkdir -p /opt/sam2_ckpts && \
    wget --no-check-certificate -qO /opt/sam2_ckpts/sam2.1_hiera_base_plus.pt \
        https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_base_plus.pt

# --------------------------------------------------------------------------- #
# Runtime ENV — HF cache + display defaults.
# --------------------------------------------------------------------------- #
ENV DISPLAY=:99 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace/hf_cache \
    XDG_RUNTIME_DIR=/tmp/runtime-root

WORKDIR /workspace

# --------------------------------------------------------------------------- #
# Patches to apply at first-run against the bind-mounted TGM-VLA source.
# Lives at /opt/tgmvla_patches/*.patch — the entrypoint applies each
# idempotently (-N) so re-runs and partial mounts don't blow up.
# --------------------------------------------------------------------------- #
COPY vla/tgm_vla/patches /opt/tgmvla_patches

# --------------------------------------------------------------------------- #
# Make /opt/venv writable by any UID so users can pass `docker run --user
# $(id -u):$(id -g)` and the first-run `pip install -e` (which writes both
# into /opt/venv site-packages AND into the bind-mounted TGM-VLA tree) still
# succeeds. Without this, --user would Permission-Denied; without --user,
# the .egg-info / marker files end up root-owned on the host bind-mount.
# /workspace is similarly opened up so first-run installs work when --user
# remaps the cwd's effective owner.
# --------------------------------------------------------------------------- #
RUN chmod -R a+rwX /opt/venv /opt/sam2_ckpts /opt/tgmvla_patches /workspace

# --------------------------------------------------------------------------- #
# Entrypoint: start Xvfb on :99 if no $DISPLAY (same logic as the RLBench
# entrypoint), THEN install TGM-VLA's vendored libs from the bind-mount
# (/workspace/TGM-VLA/tgm_vla/libs/*) on first start, gated by an import
# check (`python -c "import rlbench, pyrep, point_renderer, tgm_vla"`)
# so image rebuilds against the same bind-mount source still reinstall.
# See vla/tgm_vla/DEVNOTES.md §4 for the rationale.
# --------------------------------------------------------------------------- #
COPY vla/tgm_vla/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["bash"]
