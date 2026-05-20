# RLBench Docker — standalone headless setup.
#
# Builds an image that can run RLBench (https://github.com/stepjam/RLBench)
# headlessly in Docker on a host with an NVIDIA GPU, with REAL camera
# rendering (not the all-zero / black-frame failure mode most setups hit).
#
# Stack:
#   nvidia/cuda:12.1.1-runtime-ubuntu22.04   (CUDA base, glibc 2.35)
#     + deadsnakes Python 3.8 (PyRep needs exactly 3.8)
#     + CoppeliaSim 4.1.0 Edu Ubuntu20.04    (PyRep/RLBench pin this version)
#     + PyRep  (from https://github.com/stepjam/PyRep.git)
#     + RLBench  (from THIS repo, via COPY)
#     + VirtualGL 3.1.2  (optional vglrun path; not required for the standard
#                         Xvfb path once QT_PLUGIN_PATH is set)
#     + Xvfb + tini for the headless entrypoint
#
# The single critical discovery that makes headless rendering actually work:
#   ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
# Without this, CoppeliaSim's bundled Qt5 cannot find its `xcbglintegrations/`
# directory and silently returns all-zero frames from vision sensors. See
# docker/README.md §"Why QT_PLUGIN_PATH" for the full root-cause writeup.
#
# Build  (run from repo root):
#   docker build -t rlbench:latest --build-arg ACCEPT_RLBENCH_LICENCE=YES \
#       -f docker/Dockerfile .
#
# Run interactively:
#   docker run --rm -it --gpus all rlbench:latest
#   # inside container:
#   python -c "from rlbench.environment import Environment; ..."
#
# Render the showcase examples:
#   mkdir -p ~/rlbench-renders
#   docker run --rm --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all \
#       -v ~/rlbench-renders:/output \
#       -v $PWD/docker/examples:/examples:ro \
#       rlbench:latest python /examples/render_showcase.py
#
# Reproducibility — pin PyRep commit (RLBench is pinned to this repo's HEAD):
#   docker build --build-arg ACCEPT_RLBENCH_LICENCE=YES \
#       --build-arg PYREP_REF=<sha> -f docker/Dockerfile .

ARG CUDA_BASE=nvidia/cuda:12.1.1-runtime-ubuntu22.04
FROM ${CUDA_BASE}

# --------------------------------------------------------------------------- #
# License gate (same posture as the harness — CoppeliaSim Edu + RLBench are
# both non-redistribution / academic-only; image must NOT be pushed to a
# public registry).
# --------------------------------------------------------------------------- #
ARG ACCEPT_RLBENCH_LICENCE=
RUN if [ "$ACCEPT_RLBENCH_LICENCE" != "YES" ]; then \
        echo ""; \
        echo "============================================================"; \
        echo "Building rlbench-standalone requires accepting two licences:"; \
        echo "  1. RLBench (Imperial College London) — academic / non-commercial"; \
        echo "     https://github.com/stepjam/RLBench/blob/master/LICENSE"; \
        echo "  2. CoppeliaSim Edu — educational entities, non-commercial"; \
        echo "     https://manual.coppeliarobotics.com/en/licensing.htm"; \
        echo ""; \
        echo "Read the licences above, then re-run with:"; \
        echo "  docker build --build-arg ACCEPT_RLBENCH_LICENCE=YES ..."; \
        echo "============================================================"; \
        exit 1; \
    fi

ENV DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------------------------------- #
# System deps:
#   - deadsnakes PPA → Python 3.8 (PyRep/RLBench need exactly 3.8)
#   - GL / EGL / X11 / Xvfb for CoppeliaSim's bundled-Qt + headless rendering
#   - tini PID-1 to reap CoppeliaSim child processes
# Qt libraries are NOT installed system-wide — CoppeliaSim ships its own under
# $COPPELIASIM_ROOT/{lib,platforms}.
# --------------------------------------------------------------------------- #
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates curl wget gnupg && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y --no-install-recommends \
        python3.8 python3.8-venv python3.8-dev python3.8-distutils \
        build-essential cmake git unzip pkg-config \
        xvfb libfontconfig1 tini \
        libegl1 libegl1-mesa-dev libgl1 libgl1-mesa-glx libgles2 \
        libglib2.0-0 libsm6 libxext6 libxrender1 \
        libxcb-xinerama0 libxkbcommon-x11-0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 \
        libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 libxkbcommon0 \
        libdbus-1-3 && \
    rm -rf /var/lib/apt/lists/*

# Python 3.8 venv is the ONLY python on PATH
RUN python3.8 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel
ENV PATH=/opt/venv/bin:${PATH}

# --------------------------------------------------------------------------- #
# VirtualGL — GPU-accelerated headless OpenGL rendering.
# Works by intercepting GLX/EGL calls and redirecting them to the nvidia GPU
# via the EGL device. This is the CoppeliaSim community's standard fix for
# headless rendering in Docker on a host with nvidia GPU.
#
# Requires at runtime:
#   docker run ... --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all ... \
#     bash -c 'vglrun -d egl0 python your_script.py'
# (or pass `VGL_DISPLAY=egl0` env and prefix with `vglrun`)
# --------------------------------------------------------------------------- #
ARG VIRTUALGL_VERSION=3.1.2
RUN wget -qO /tmp/vgl.deb \
        https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION}/virtualgl_${VIRTUALGL_VERSION}_amd64.deb && \
    apt-get update && apt-get install -y --no-install-recommends /tmp/vgl.deb && \
    rm /tmp/vgl.deb && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------------- #
# CoppeliaSim 4.1.0 Edu — exact version (newer = PyRep segfault).
# The Ubuntu 20.04 binary runs on Ubuntu 22.04 / 24.04 hosts because the
# container is 22.04 and CoppeliaSim bundles its own Qt + libs.
#
# OpenGL3 renderer plugin is kept ENABLED here — with VirtualGL providing real
# nvidia GLX/EGL at runtime, the plugin works correctly and gives higher
# render quality than the built-in fallback. Without `vglrun`, the plugin
# segfaults under Xvfb (no usable GLX); always prefix invocations with vglrun.
# --------------------------------------------------------------------------- #
ENV COPPELIASIM_ROOT=/opt/coppeliasim
RUN mkdir -p ${COPPELIASIM_ROOT} && \
    wget -qO /tmp/cs.tar.xz \
        https://downloads.coppeliarobotics.com/V4_1_0/CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz && \
    tar -xf /tmp/cs.tar.xz -C ${COPPELIASIM_ROOT} --strip-components=1 && \
    rm /tmp/cs.tar.xz

ENV LD_LIBRARY_PATH=${COPPELIASIM_ROOT}:${LD_LIBRARY_PATH} \
    QT_QPA_PLATFORM_PLUGIN_PATH=${COPPELIASIM_ROOT}/platforms

# --------------------------------------------------------------------------- #
# PyRep + RLBench — commit-pinnable via build args.
# Default = HEAD of master on each repo (matches the harness behaviour).
# --------------------------------------------------------------------------- #
ARG PYREP_REPO=https://github.com/stepjam/PyRep.git
ARG PYREP_REF=master
RUN git clone ${PYREP_REPO} /opt/PyRep && \
    cd /opt/PyRep && git checkout ${PYREP_REF} && \
    pip install --no-cache-dir -e . && \
    rm -rf /opt/PyRep/.git

# RLBench from THIS repo (which IS a fork of stepjam/RLBench). The .dockerignore
# excludes docker/, .git/, and other non-essentials from the build context.
COPY . /opt/RLBench
RUN cd /opt/RLBench && pip install --no-cache-dir -e .

# Common VLA-eval companions (scipy for Rotation, Pillow for image IO,
# gymnasium for the rlbench.gym wrapper if used).
RUN pip install --no-cache-dir scipy pillow gymnasium

# --------------------------------------------------------------------------- #
# CRITICAL Qt plugin discovery fix.
#
# CoppeliaSim 4.1.0 ships Qt's XCB GL integration plugins at
# /opt/coppeliasim/xcbglintegrations/ (next to the Qt5 libs, not under
# platforms/). Without QT_PLUGIN_PATH set, the bundled Qt's xcb platform
# plugin (loaded from QT_QPA_PLATFORM_PLUGIN_PATH=/opt/coppeliasim/platforms)
# cannot find xcbglintegrations/ and gives up on GL context creation:
#   "QXcbIntegration: Cannot create platform OpenGL context,
#    neither GLX nor EGL are enabled"
# → vision sensors return all-zero (black) frames.
#
# QT_PLUGIN_PATH adds COPPELIASIM_ROOT itself to Qt's plugin search, where the
# xcbglintegrations/ subdir lives. With this set, RenderMode.OPENGL3 (default)
# and RenderMode.OPENGL both produce real frames under Xvfb's software GLX —
# no VirtualGL needed.
# Discovered by multi-agent investigation 2026-05-20.
# --------------------------------------------------------------------------- #
ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}

WORKDIR /workspace

# --------------------------------------------------------------------------- #
# Entrypoint: start Xvfb on :99 if no $DISPLAY, then exec the user command.
# Default CMD = bash for interactive use.
# --------------------------------------------------------------------------- #
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["bash"]
