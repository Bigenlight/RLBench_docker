# BridgeVLA Docker — RLBench + BridgeVLA training / eval stack.
#
# Builds an image that combines a working headless RLBench setup (per
# docker/Dockerfile) with the BridgeVLA (https://github.com/...) finetuning
# dependencies (PyTorch 2.5.1 + CUDA 12.1, xformers, pytorch3d, transformers,
# accelerate, open3d, CLIP, etc.).
#
# Stack:
#   nvidia/cuda:12.1.1-runtime-ubuntu22.04   (CUDA base, glibc 2.35)
#     + deadsnakes Python 3.9              (BridgeVLA env spec)
#     + CoppeliaSim 4.1.0 Edu Ubuntu20.04   (PyRep/RLBench pin this version)
#     + PyRep                                (pinned commit)
#     + RLBench fork buttomnutstoast        (pinned commit; BridgeVLA-compatible)
#     + PyTorch 2.5.1 + xformers + pytorch3d
#     + Xvfb + tini for the headless entrypoint
#
# BridgeVLA itself is NOT cloned into the image — it is bind-mounted from the
# host at /workspace/BridgeVLA so the user can edit code on the host. The
# entrypoint runs `pip install -e` on BridgeVLA's three vendored libs
# (YARR / peract_colab / point-renderer) plus the main `bridgevla` package
# on first container start.
#
# Critical Qt plugin discovery fix (same as docker/Dockerfile):
#   ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
# Without this, CoppeliaSim's bundled Qt5 silently returns all-zero camera
# frames under Xvfb. See docker/README.md §"Why QT_PLUGIN_PATH".
#
# Build  (run from repo root):
#   docker build -t bridgevla:latest --build-arg ACCEPT_BRIDGEVLA_LICENCE=YES \
#       -f vla/bridgevla/Dockerfile .
#
# Run interactively (mount BridgeVLA source + HF cache):
#   docker run --rm -it --gpus all \
#       -v ~/BridgeVLA:/workspace/BridgeVLA \
#       -v ~/.cache/huggingface:/workspace/hf_cache \
#       bridgevla:latest
#
# Expected final image size: ~27 GB on disk uncompressed (CUDA runtime+dev,
# PyTorch + xformers + pytorch3d, CoppeliaSim 4.1.0 Edu binaries).

ARG CUDA_BASE=nvidia/cuda:12.1.1-runtime-ubuntu22.04
FROM ${CUDA_BASE}

# --------------------------------------------------------------------------- #
# License gate — CoppeliaSim Edu, RLBench, and BridgeVLA are all
# non-redistribution / academic-only; image must NOT be pushed to a public
# registry. Same posture as docker/Dockerfile.
# --------------------------------------------------------------------------- #
ARG ACCEPT_BRIDGEVLA_LICENCE=
RUN if [ "$ACCEPT_BRIDGEVLA_LICENCE" != "YES" ]; then \
        echo ""; \
        echo "============================================================"; \
        echo "Building bridgevla image requires accepting three licences:"; \
        echo "  1. RLBench (Imperial College London) — academic / non-commercial"; \
        echo "     https://github.com/stepjam/RLBench/blob/master/LICENSE"; \
        echo "  2. CoppeliaSim Edu — educational entities, non-commercial"; \
        echo "     https://manual.coppeliarobotics.com/en/licensing.htm"; \
        echo "  3. BridgeVLA — see upstream repo LICENSE"; \
        echo ""; \
        echo "Read the licences above, then re-run with:"; \
        echo "  docker build --build-arg ACCEPT_BRIDGEVLA_LICENCE=YES ..."; \
        echo "============================================================"; \
        exit 1; \
    fi

ENV DEBIAN_FRONTEND=noninteractive

ARG PYTHON_VERSION=3.9

# --------------------------------------------------------------------------- #
# System deps:
#   - deadsnakes PPA → Python 3.9 (BridgeVLA env spec)
#   - GL / EGL / X11 / Xvfb for CoppeliaSim's bundled-Qt + headless rendering
#   - extra xcb libs + ffmpeg for BridgeVLA (pyrender, video IO, PyQt6)
#   - tini PID-1 to reap CoppeliaSim child processes
# Qt libraries are NOT installed system-wide — CoppeliaSim ships its own under
# $COPPELIASIM_ROOT/{lib,platforms}. PyQt6 is installed via pip later.
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates curl wget gnupg && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-distutils \
        build-essential cmake git unzip pkg-config \
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
    rm -rf /var/lib/apt/lists/*

# Python 3.9 venv is the ONLY python on PATH
RUN python${PYTHON_VERSION} -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel
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
    rm /tmp/cs.tar.xz

# --------------------------------------------------------------------------- #
# CRITICAL Qt plugin discovery fix (see docker/Dockerfile for full writeup).
# QT_PLUGIN_PATH=$COPPELIASIM_ROOT lets the bundled Qt find xcbglintegrations/
# → vision sensors produce real frames instead of all-zero blacks.
# --------------------------------------------------------------------------- #
ENV LD_LIBRARY_PATH=${COPPELIASIM_ROOT}:${LD_LIBRARY_PATH} \
    QT_QPA_PLATFORM_PLUGIN_PATH=${COPPELIASIM_ROOT}/platforms \
    QT_PLUGIN_PATH=${COPPELIASIM_ROOT}

# --------------------------------------------------------------------------- #
# PyRep + RLBench (buttomnutstoast fork) — commit-pinnable via build args.
# RLBench here is the BridgeVLA-compatible fork, NOT this repo's RLBench.
# --------------------------------------------------------------------------- #
ARG PYREP_REPO=https://github.com/stepjam/PyRep.git
ARG PYREP_REF=231a1ac6b0a179cff53c1d403d379260b9f05f2f
ARG RLBENCH_REPO=https://github.com/buttomnutstoast/RLBench.git
ARG RLBENCH_REF=587a6a0e6dc8cd36612a208724eb275fe8cb4470

RUN mkdir -p /opt/bridgevla_libs && \
    git clone ${PYREP_REPO} /opt/bridgevla_libs/PyRep && \
    cd /opt/bridgevla_libs/PyRep && git checkout ${PYREP_REF} && \
    git clone ${RLBENCH_REPO} /opt/bridgevla_libs/RLBench && \
    cd /opt/bridgevla_libs/RLBench && git checkout ${RLBENCH_REF}

# --------------------------------------------------------------------------- #
# Pip install sequence — ORDER MATTERS.
# Splitting into per-concern RUN layers so a single failure doesn't invalidate
# the whole pip cache layer when debugging the dependency graph.
# --------------------------------------------------------------------------- #

# Build tooling + pinned pip/setuptools (later pins break under newer pip).
# cffi + numpy installed up-front because PyRep's setup.py imports cffi at
# metadata-generation time (cffi_build/cffi_build.py), before its own
# install_requires can run. In BridgeVLA's install_rlbench.sh this is masked
# because the bridgevla package is installed first; we don't have that luxury.
RUN pip install --no-cache-dir wheel ninja pyyaml cffi numpy && \
    pip install --no-cache-dir pip==25.0.1 setuptools==76.1.0

# open3d before PyRep/RLBench — its deps (numpy etc.) shouldn't fight with
# torch's later.
RUN pip install --no-cache-dir open3d

# Editable PyRep + RLBench (clones already on disk, pinned above).
RUN pip install --no-cache-dir -e /opt/bridgevla_libs/PyRep
RUN pip install --no-cache-dir -e /opt/bridgevla_libs/RLBench

# xformers from PyTorch's CUDA-12.1 index — pulls a CUDA-matched torch as a
# transitive dep, which we then OVERRIDE with the exact 2.5.1 pair below.
RUN pip install --no-cache-dir -U xformers \
        --index-url https://download.pytorch.org/whl/cu121

# Pin torch to 2.5.1 via torchaudio/torchvision (those wheels pin torch==2.5.1).
RUN pip install --no-cache-dir torchaudio==2.5.1 torchvision==0.20.1

# HF stack — accelerate>=0.26.0 required by transformers 4.51.3.
RUN pip install --no-cache-dir 'accelerate>=0.26.0' transformers==4.51.3

# OpenAI CLIP from git (no pypi release).
RUN pip install --no-cache-dir git+https://github.com/openai/CLIP.git

# UI / logging / video / config libs used by BridgeVLA scripts.
RUN pip install --no-cache-dir pyqt6 yacs wandb ffmpeg-python

# pytorch3d from git@stable — long build; slowest single step in this file.
RUN pip install --no-cache-dir \
        git+https://github.com/facebookresearch/pytorch3d.git@stable

# opencv headless dance — pytorch3d / pyrender / others keep dragging in the
# non-headless build, which breaks Qt under Xvfb. The double install+uninstall
# is required because some transitive deps re-resolve mid-install.
RUN pip uninstall -y opencv-python opencv-contrib-python opencv-python-headless && \
    pip install --no-cache-dir opencv-python-headless && \
    pip uninstall -y opencv-python-headless && \
    pip install --no-cache-dir opencv-python-headless

# BridgeVLA's setup.py deps — installed up-front so first container start
# doesn't pay this cost. (setup.py itself runs at container start via the
# entrypoint, but with --no-deps so these survive.)
RUN pip install --no-cache-dir \
        numpy scipy einops pyrender omegaconf natsort cffi pandas \
        tensorflow pyquaternion matplotlib bitsandbytes transforms3d

# CUDA dev headers / nvcc — required at container start to compile BridgeVLA's
# `point-renderer` extension (custom CUDA op, no prebuilt wheel). It pulls in
# curand / cublas etc., so install the broader cuda-libraries-dev metapackage.
# Placed near the end to maximize layer cache reuse on incremental rebuilds.
# pytorch3d earlier shipped a prebuilt wheel so didn't need this.
RUN apt-get update && apt-get install -y --no-install-recommends \
        cuda-nvcc-12-1 cuda-cudart-dev-12-1 cuda-libraries-dev-12-1 && \
    rm -rf /var/lib/apt/lists/*
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH}

# --------------------------------------------------------------------------- #
# Runtime ENV — HF cache + display defaults.
# --------------------------------------------------------------------------- #
ENV DISPLAY=:99 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace/hf_cache

WORKDIR /workspace

# --------------------------------------------------------------------------- #
# Entrypoint: start Xvfb on :99 if no $DISPLAY (same logic as the RLBench
# entrypoint), THEN install BridgeVLA's vendored libs from the bind-mount
# (/workspace/BridgeVLA/finetune/bridgevla/libs/*) on first start, guarded by
# a marker file at /workspace/.bridgevla_libs_installed.
# --------------------------------------------------------------------------- #
COPY vla/bridgevla/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["bash"]
