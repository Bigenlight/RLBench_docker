# SpatialActor Docker — RLBench + SpatialActor (AAAI 2026) eval stack.
#
# Builds a self-contained image to evaluate SpatialActor
# (https://github.com/shihao1895/SpatialActor — "SpatialActor: Exploring
# Disentangled Spatial Representations for Robust Robotic Manipulation") on
# headless RLBench, on a single 12 GB GPU (verified RTX 3060).
#
# Why this image does NOT extend vla/bridgevla or docker/ : SpatialActor pins a
# much OLDER stack than every other overlay in this repo —
#   Python 3.9 + torch 1.12.1 + CUDA 11.3  (BridgeVLA = torch 2.5.1 + CUDA 12.1)
#   pytorch3d 0.7.5 + xformers 0.0.16, distributed ONLY as conda binaries built
#   for py39_cu113_pyt1121, which have no usable pip wheels.
# So this image is built from a CUDA 11.3 *devel* base (nvcc 11.3 for the custom
# point-renderer CUDA op) with Miniconda reproducing SpatialActor's own README
# install recipe. See vla/README.md for the per-VLA self-contained rationale.
#
# Stack:
#   nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04   (CUDA base + nvcc, glibc 2.31)
#     + Miniconda env `spact`, Python 3.9          (SpatialActor env spec)
#     + torch 1.12.1+cu113 / torchvision 0.13.1    (pip, cu113 index)
#     + cudatoolkit 11.3 + pytorch3d 0.7.5 + xformers 0.0.16  (conda binaries)
#     + CoppeliaSim 4.1.0 Edu Ubuntu20.04          (PyRep/RLBench pin this)
#     + PyRep / RLBench(buttomnutstoast) / YARR(NVlabs)  (cloned + pinned)
#     + Xvfb + tini for the headless entrypoint
#
# The SpatialActor repo itself is NOT cloned into the image — it is bind-mounted
# from the host at /workspace/SpatialActor so user edits apply immediately. The
# entrypoint installs its two in-repo libs (third_libs/point-renderer + the
# spatial_actor package) on first container start. See vla/spatial_actor/README.md.
#
# Critical Qt plugin discovery fix (same as docker/Dockerfile):
#   ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
# Without it, CoppeliaSim's bundled Qt5 silently returns all-zero camera frames
# under Xvfb. See docker/README.md §"Why QT_PLUGIN_PATH".
#
# Build (run from repo root):
#   docker build -t spatial_actor:latest \
#       --build-arg ACCEPT_SPATIALACTOR_LICENCE=YES \
#       -f vla/spatial_actor/Dockerfile .
#
# Expected final image size: ~25-30 GB on disk (CUDA devel + conda + torch +
# pytorch3d + xformers + CoppeliaSim 4.1.0 Edu binaries).

ARG CUDA_BASE=nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04
FROM ${CUDA_BASE}

# --------------------------------------------------------------------------- #
# License gate — CoppeliaSim Edu, RLBench, and SpatialActor are all
# non-redistribution / academic-only; image must NOT be pushed to a public
# registry. Same posture as docker/Dockerfile and vla/bridgevla/Dockerfile.
# --------------------------------------------------------------------------- #
ARG ACCEPT_SPATIALACTOR_LICENCE=
RUN if [ "$ACCEPT_SPATIALACTOR_LICENCE" != "YES" ]; then \
        echo ""; \
        echo "============================================================"; \
        echo "Building spatial_actor image requires accepting three licences:"; \
        echo "  1. RLBench (Imperial College London) — academic / non-commercial"; \
        echo "     https://github.com/stepjam/RLBench/blob/master/LICENSE"; \
        echo "  2. CoppeliaSim Edu — educational entities, non-commercial"; \
        echo "     https://manual.coppeliarobotics.com/en/licensing.htm"; \
        echo "  3. SpatialActor — see upstream repo (shihao1895/SpatialActor)"; \
        echo ""; \
        echo "Read the licences above, then re-run with:"; \
        echo "  docker build --build-arg ACCEPT_SPATIALACTOR_LICENCE=YES ..."; \
        echo "============================================================"; \
        exit 1; \
    fi

ENV DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------- #
# System deps:
#   - GL / EGL / X11 / Xvfb for CoppeliaSim's bundled-Qt + headless rendering
#   - extra xcb libs + ffmpeg (eval.py shells out to ffmpeg to encode videos)
#   - build-essential / cmake / git for the point-renderer CUDA build + clones
#   - tini PID-1 to reap CoppeliaSim child processes
# Qt libraries are NOT installed system-wide — CoppeliaSim ships its own under
# $COPPELIASIM_ROOT/{lib,platforms}. Python comes from Miniconda, not apt.
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git unzip pkg-config build-essential cmake \
        xvfb libfontconfig1 tini ffmpeg libffi-dev \
        libegl1 libegl1-mesa-dev libgl1 libgl1-mesa-glx libgl1-mesa-dri libgles2 \
        libglib2.0-0 libsm6 libxext6 libxrender1 \
        libxcb-xinerama0 libxkbcommon-x11-0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 libxkbcommon0 \
        libxcb-cursor0 libxcb-xinput0 libx11-xcb1 libxcb1 \
        libxcb-render0 libxcb-shm0 libxcb-util1 libxcb-glx0 \
        libdbus-1-3 && \
    rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------------- #
# Miniconda + the `spact` env (Python 3.9). Miniconda is required (not just
# pip) because pytorch3d 0.7.5 and xformers 0.0.16 are only distributed as
# conda binaries for this exact py39_cu113_pyt1121 ABI — see Step 2 below.
# The env's bin is put first on PATH so `python` / `pip` resolve to it without
# needing `conda activate` in every RUN layer.
# --------------------------------------------------------------------------- #
RUN wget -qO /tmp/mc.sh \
        https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash /tmp/mc.sh -b -p /opt/conda && rm /tmp/mc.sh
ENV PATH=/opt/conda/bin:${PATH}
# Recent Miniconda gates the Anaconda default channels behind a Terms-of-Service
# acceptance; without this `conda create` aborts with a ToS error. Accept it for
# the two default channels (the documented remedy) before any conda op.
ENV CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
RUN conda create -y -n spact python=3.9 && conda clean -ya
ENV PATH=/opt/conda/envs/spact/bin:/opt/conda/bin:/usr/local/cuda/bin:${PATH}
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# --------------------------------------------------------------------------- #
# Step 1 (SpatialActor README): torch 1.12.1 + CUDA 11.3 + cudatoolkit.
# --------------------------------------------------------------------------- #
RUN pip install --no-cache-dir \
        torch==1.12.1+cu113 torchvision==0.13.1+cu113 torchaudio==0.12.1 \
        --extra-index-url https://download.pytorch.org/whl/cu113
RUN conda install -n spact -y -c "nvidia/label/cuda-11.3.1" cudatoolkit=11.3 && \
    conda clean -ya

# --------------------------------------------------------------------------- #
# Step 2 (SpatialActor README): PyTorch3D 0.7.5 + xformers 0.0.16.
# Installed by direct conda-package URL with --no-deps. The --no-deps is
# CRITICAL: both .tar.bz2 packages declare a hard dependency on the *conda*
# package `pytorch 1.12.1`, which conda cannot see being satisfied by the
# pip-installed torch 1.12.1+cu113 wheel (pip interop is off by default). Without
# --no-deps conda would helpfully install a conda `pytorch 1.12.1` build —
# overwriting our cu113 wheel with a (likely CPU) build and silently breaking
# CUDA. With --no-deps the tarballs just unpack into the env expecting the pip
# torch + the cudatoolkit installed above. pytorch3d is a HARD import
# (augmentation.py); xformers is used via try/except (DINOv2 attention) but
# installed for fidelity. fvcore/iopath (pytorch3d runtime deps) are baked below.
# --------------------------------------------------------------------------- #
RUN conda install -n spact -y --no-deps \
        https://anaconda.org/pytorch3d/pytorch3d/0.7.5/download/linux-64/pytorch3d-0.7.5-py39_cu113_pyt1121.tar.bz2 && \
    conda clean -ya
RUN conda install -n spact -y --no-deps \
        https://anaconda.org/xformers/xformers/0.0.16/download/linux-64/xformers-0.0.16-py39_cu11.3_pyt1.12.1.tar.bz2 && \
    conda clean -ya
# pytorch3d runtime deps (it imports fvcore/iopath); installed via pip since the
# conda packages above were --no-deps. Light, pure-python.
RUN pip install --no-cache-dir fvcore iopath

# --------------------------------------------------------------------------- #
# CoppeliaSim 4.1.0 Edu — exact version (newer = PyRep segfault). Edu (not the
# Player build the upstream README links) to match this repo's other overlays
# and the licence gate above; PyRep 4.1.0 works with either.
# --------------------------------------------------------------------------- #
ENV COPPELIASIM_ROOT=/opt/coppeliasim
RUN mkdir -p ${COPPELIASIM_ROOT} && \
    wget -qO /tmp/cs.tar.xz \
        https://downloads.coppeliarobotics.com/V4_1_0/CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz && \
    tar -xf /tmp/cs.tar.xz -C ${COPPELIASIM_ROOT} --strip-components=1 && \
    rm /tmp/cs.tar.xz

# --------------------------------------------------------------------------- #
# CRITICAL Qt plugin discovery fix (see docker/Dockerfile for the full writeup).
# QT_PLUGIN_PATH=$COPPELIASIM_ROOT lets the bundled Qt find xcbglintegrations/
# → vision sensors produce real frames instead of all-zero blacks under Xvfb.
# --------------------------------------------------------------------------- #
ENV LD_LIBRARY_PATH=${COPPELIASIM_ROOT}:${LD_LIBRARY_PATH} \
    QT_QPA_PLATFORM_PLUGIN_PATH=${COPPELIASIM_ROOT}/platforms \
    QT_PLUGIN_PATH=${COPPELIASIM_ROOT}

# --------------------------------------------------------------------------- #
# Step 4 (SpatialActor README): PyRep + YARR + RLBench. The upstream README
# leaves these unpinned; we pin to the same commits BridgeVLA verified against
# CoppeliaSim 4.1.0 (PyRep, buttomnutstoast/RLBench).
#
# YARR: the **rvt branch** (NVlabs/YARR), NOT the default `main`. SpatialActor is
# RVT-lineage and imports `yarr.agents.agent.TextSummary`, which exists only on
# the rvt/peract branches — `main` lacks it, so a `main` clone fails at import
# with "cannot import name 'TextSummary'". (The upstream README's bare
# `git clone NVlabs/YARR` defaults to main and has this latent bug.)
# Override via --build-arg if needed.
# --------------------------------------------------------------------------- #
ARG PYREP_REPO=https://github.com/stepjam/PyRep.git
ARG PYREP_REF=231a1ac6b0a179cff53c1d403d379260b9f05f2f
ARG RLBENCH_REPO=https://github.com/buttomnutstoast/RLBench.git
ARG RLBENCH_REF=587a6a0e6dc8cd36612a208724eb275fe8cb4470
ARG YARR_REPO=https://github.com/NVlabs/YARR.git
ARG YARR_REF=f4aaeea183321e6b526166249119071e64252ad2

RUN mkdir -p /opt/spact_libs && \
    git clone ${PYREP_REPO} /opt/spact_libs/PyRep && \
    cd /opt/spact_libs/PyRep && git checkout ${PYREP_REF} && \
    git clone ${RLBENCH_REPO} /opt/spact_libs/RLBench && \
    cd /opt/spact_libs/RLBench && git checkout ${RLBENCH_REF} && \
    git clone ${YARR_REPO} /opt/spact_libs/YARR && \
    cd /opt/spact_libs/YARR && git checkout ${YARR_REF}

# Build tooling + cffi + numpy up-front. PyRep's setup.py imports cffi at
# metadata-generation time (cffi_build/cffi_build.py), before its own
# install_requires can run — and modern pip isolates the build env, so we MUST
# install these here AND pass --no-build-isolation below so the build sees them.
#
# setuptools is PINNED to 69.5.1 (SpatialActor's own pin): newer setuptools
# (>=81) removed the bundled `pkg_resources`, but torch 1.12.1's
# torch.utils.cpp_extension does `from pkg_resources import packaging`, so a
# too-new setuptools breaks the point-renderer CUDA compile (and any runtime
# pkg_resources import) with "No module named 'pkg_resources'".
RUN pip install --no-cache-dir 'setuptools==69.5.1' 'wheel==0.41.2' \
        ninja pyyaml cffi 'numpy==1.26.4'

# Editable PyRep + RLBench (clones already on disk, pinned above).
# --no-build-isolation: PyRep's build imports cffi (and these repos are plain
# setup.py projects); without it pip builds in an isolated env missing cffi and
# fails with "No module named 'cffi'". Build deps are already in the env above.
RUN pip install --no-cache-dir --no-build-isolation -e /opt/spact_libs/PyRep
RUN pip install --no-cache-dir --no-build-isolation -e /opt/spact_libs/RLBench

# YARR: apply the single-episode summary-flush patch (so a 1-episode smoke eval
# still emits scores + a VideoSummary), THEN install editable. This patch is
# baked here because YARR lives in the image, not the bind-mount.
COPY vla/spatial_actor/patches/02-enable-singleep-summaries.patch /tmp/02-yarr.patch
RUN cd /opt/spact_libs/YARR && \
    patch -p1 --forward < /tmp/02-yarr.patch && \
    pip install --no-cache-dir --no-build-isolation -e .

# --------------------------------------------------------------------------- #
# SpatialActor's runtime deps, baked here so the entrypoint can install the
# spatial_actor package itself with --no-deps. Curated from its setup.py with
# two deliberate DROPS: triton==2.0.0 (requires torch>=2.0, conflicts with our
# torch 1.12.1, and is never imported) and tensorflow==2.17.0 (never imported,
# bundles its own LLVM which can segfault CoppeliaSim). bitsandbytes IS kept
# (cfg.yaml sets bnb: true). jupyter is dropped (not needed for eval).
# --------------------------------------------------------------------------- #
RUN pip install --no-cache-dir \
        einops pyrender omegaconf natsort cffi pandas yacs imageio \
        trimesh meshcat pyquaternion matplotlib \
        'pycparser==2.21' 'numpy==1.26.4' 'scipy==1.13.1' \
        'transformers==4.40.1' 'bitsandbytes==0.38.1' 'transforms3d==0.4.2'
RUN pip install --no-cache-dir git+https://github.com/openai/CLIP.git

# opencv headless: eval.py imports cv2; some transitive deps drag in the
# non-headless build whose bundled Qt plugin breaks under Xvfb. Force the
# headless build to win (see SpatialActor README §Evaluation Step 1).
# --no-deps is REQUIRED: opencv-python-headless's `numpy>=1.17.0` dep, under a
# plain (re)install, resolves to numpy 2.0.x and uninstalls our pinned 1.26.4 —
# and numpy 2.0 is ABI-incompatible with torch 1.12.1. So install cv2 without
# touching deps, then re-assert the numpy pin defensively.
RUN pip uninstall -y opencv-python opencv-contrib-python opencv-python-headless \
        >/dev/null 2>&1 || true && \
    pip install --no-cache-dir --no-deps 'opencv-python-headless==4.11.0.86' && \
    pip install --no-cache-dir 'numpy==1.26.4'

# --------------------------------------------------------------------------- #
# CUDA build env for the point-renderer extension (compiled at first container
# start from the bind-mount). nvcc + headers come from the devel base.
# --------------------------------------------------------------------------- #
ENV CUDA_HOME=/usr/local/cuda

# --------------------------------------------------------------------------- #
# Runtime ENV — display default + bitsandbytes welcome banner off.
# DISPLAY=:99 is the default the entrypoint targets; the entrypoint starts Xvfb
# on :99 whenever DISPLAY is empty OR is this bare :99 default with no X server
# already listening, so eval works with or without `-e DISPLAY=` on `docker run`.
# (No HF_HOME: SpatialActor eval downloads nothing from the HF hub — the depth
# weights are bind-mounted and CLIP/ResNet come from their own libs' caches.)
# --------------------------------------------------------------------------- #
ENV DISPLAY=:99 \
    PYTHONUNBUFFERED=1 \
    BITSANDBYTES_NOWELCOME=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all

# CRITICAL: force the SYSTEM libffi.so.7 into every process. Miniconda ships a
# broken `libffi.so.7 -> libffi.so.8.1.4` symlink (ABI-incompatible); conda's
# Python loads libffi.so.8 first, so when CoppeliaSim's Mesa swrast driver pulls
# in libLLVM-12 (which NEEDS libffi.so.7 / LIBFFI_BASE_7.0 symbols) the loader
# resolves against the already-loaded libffi 8 and fails with
# "undefined symbol: ffi_type_sint32, version LIBFFI_BASE_7.0" -> swrast fails to
# load -> CoppeliaSim segfaults creating a vision-sensor GL context (all-black /
# crash). Preloading the real libffi 7 provides the 7.0-versioned symbols. This
# does NOT disturb torch/pytorch3d (they use conda's libffi.so.8, still present)
# nor torch's newer libstdc++ (deliberately NOT preloaded).
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libffi.so.7

WORKDIR /workspace

COPY vla/spatial_actor/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["bash"]
