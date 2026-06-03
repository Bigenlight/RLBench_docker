# SpatialActor on RLBench — Standalone Docker Eval

Build & run a self-contained container for [SpatialActor](https://github.com/shihao1895/SpatialActor)
("SpatialActor: Exploring Disentangled Spatial Representations for Robust
Robotic Manipulation", **AAAI 2026 Oral** — [arXiv 2511.09555](https://arxiv.org/abs/2511.09555))
against RLBench eval, headlessly, on a single mid-range GPU (verified RTX 3060
12 GB), **without** the official PerAct demo dataset.

This is a VLA overlay under [`vla/`](../). For the directory pattern and how to
add a new VLA, see [`vla/README.md`](../README.md). For the base RLBench Docker
setup (different Python / RLBench fork — not extended here), see
[`docker/README.md`](../../docker/README.md). The closest sibling overlay is
[`vla/bridgevla/`](../bridgevla/); this README follows the same shape.

## Prerequisites (host machine)

Before anything, the host needs:

- **Linux** with an **NVIDIA GPU**. SpatialActor's eval at batch size 1 (4 input
  cameras — front + left/right shoulder + wrist — rendered to 3 orthographic
  views) fits comfortably in **~3-4 GB VRAM** (much lighter than BridgeVLA), so a
  12 GB card is plenty; even 6-8 GB should work.
- **NVIDIA driver** installed (`nvidia-smi` works on the host).
- **Docker** ≥ 20.10 (`docker --version`).
- **NVIDIA Container Toolkit** so Docker can see the GPU. Verify with:
  ```bash
  docker run --rm --gpus all nvidia/cuda:11.3.1-base-ubuntu20.04 nvidia-smi
  ```
  If this prints the GPU table you're good; if it errors, fix this first.
- **Disk**: ~40 GB free (Docker image ~25-30 GB, SpatialActor checkpoint
  ~1.4 GB, DepthAnythingV2 weights ~0.4 GB, repo + caches + headroom ~5 GB).
- **`python3` + `pip`** on the host for the `huggingface_hub` CLI used to
  download the checkpoint + the depth-expert weights.

You do **not** need: CoppeliaSim, PyTorch, conda, or the RLBench fork on the
host. Everything is inside the container.

> **Note**: Building `docker/Dockerfile` (the plain-RLBench dev image) is NOT
> needed for SpatialActor eval. Only the `vla/spatial_actor/Dockerfile` below.

## The non-obvious bits this setup solves

1. **Old, conda-only stack.** SpatialActor pins **Python 3.9 + torch 1.12.1 +
   CUDA 11.3**, and **pytorch3d 0.7.5 / xformers 0.0.16 are distributed only as
   conda binaries** for the `py39_cu113_pyt1121` ABI (no usable pip wheels). The
   image is therefore built from a **CUDA 11.3 *devel* base** (for `nvcc`) with
   **Miniconda** reproducing SpatialActor's own README install recipe — unlike
   every other overlay in this repo, which is pip-only on CUDA 12.1.
2. **CoppeliaSim headless Qt5 plugin** — `QT_PLUGIN_PATH=$COPPELIASIM_ROOT`, the
   same discovery as the base `docker/Dockerfile` (see its README for the full
   root-cause writeup). Without it vision sensors return all-zero frames.
3. **No PerAct demo dataset.** SpatialActor's `CustomMultiTaskRLBenchEnv.reset_to_demo`
   loads a stored demo from disk to set the scene. Patched to fall back to
   `task.reset()` (fresh procedural scene, variation 0) when no dataset is
   present, so eval runs without the >100 GB dataset. Reproducibility against
   paper numbers is lost, but the pipeline runs end-to-end.
4. **`triton` / `tensorflow` dependency clash.** SpatialActor's `setup.py` pins
   `triton==2.0.0` (requires torch ≥ 2.0 — conflicts with torch 1.12.1) and
   `tensorflow==2.17.0` (bundles its own LLVM, can segfault CoppeliaSim).
   Neither is ever imported, so both are dropped: real deps are baked into the
   image and the `spatial_actor` package is installed with `--no-deps`.
5. **Single-episode summary flush.** NVlabs/YARR's `_SimpleAccumulator.pop()`
   only flushed after `> 1` finished episodes, so an `--eval-episodes 1` smoke
   test produced no score and no video. Relaxed to `>= 1` (baked into the
   image's YARR clone).
6. **Depth-expert weights at a fixed path.** The checkpoint's `cfg.yaml` sets
   `dep_exp_path: /data/ckpt/spact/pretrained`, and the model loads
   `${dep_exp_path}/depth_anything_v2_vitb.pth` at construction time. We satisfy
   this by **bind-mounting** the downloaded DepthAnythingV2 weights to that exact
   path inside the container (no cfg edit needed).

> Why this overlay is fully self-contained (no `FROM rlbench-base:latest`): see
> reason 1 above — the Python / torch / CUDA pins are incompatible with the base
> image's. Each VLA folder builds its own image from `nvidia/cuda:...` directly;
> the shared *pattern* (CoppeliaSim install, Qt env, Xvfb entrypoint) is
> documented in [`vla/README.md`](../README.md).

---

## TL;DR

```bash
# 0. Clone THIS repo (the one you're reading this README from):
git clone https://github.com/Bigenlight/RLBench_docker.git
cd RLBench_docker
REPO_ROOT=$(pwd)   # remember it for step 3

# 1. Build the SpatialActor Docker image (~40-60 min cold; ~10 sec when cached):
docker build -t spatial_actor:latest \
    --build-arg ACCEPT_SPATIALACTOR_LICENCE=YES \
    -f vla/spatial_actor/Dockerfile .

# > If the build fails downloading CoppeliaSim 4.1.0 Edu (URL dead or network
# > blocked), grab `CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz` manually from
# > https://www.coppeliarobotics.com/previousVersions and edit
# > vla/spatial_actor/Dockerfile to COPY the local tarball instead of wget.

# 2. Clone SpatialActor upstream (will be bind-mounted into the container):
git clone https://github.com/shihao1895/SpatialActor.git ~/SpatialActor

# 3. Apply the demo-bypass patch to ~/SpatialActor (one-time, idempotent):
PATCH_DIR="${REPO_ROOT}/vla/spatial_actor/patches"
cd ~/SpatialActor
patch -p1 --forward < "$PATCH_DIR/01-bypass-demo-loading.patch"
cd -

# Sanity check the patch landed (should print the fallback line):
grep -n "fall back to a fresh procedural scene" \
    ~/SpatialActor/spatial_actor/envs/custom_rlbench_env.py \
    && echo "patch 01 applied ✓" || echo "patch 01 did NOT apply — re-check above"
# (Patch 02 — the YARR single-episode flush — is baked into the image at build
#  time, so there is nothing to apply on the host for it.)

# 4. Install huggingface_hub CLI on the host (one-time, ~10 MB):
pip install --user huggingface_hub
# Recent huggingface_hub (>=0.19) exposes `hf` as the primary CLI; older
# installs expose only `huggingface-cli` — swap the command in steps 5-6 if so.

# 5. Download the SpatialActor checkpoint (~1.4 GB; model_45.pth + cfg.yaml):
mkdir -p ~/spact_ckpt
hf download shihao1895/spact-rlbench --local-dir ~/spact_ckpt

# 6. Download the DepthAnythingV2-Base depth-expert weights (~0.4 GB):
mkdir -p ~/spact_pretrained
hf download depth-anything/Depth-Anything-V2-Base \
    depth_anything_v2_vitb.pth --local-dir ~/spact_pretrained

# 7. Run a 1-episode close_jar smoke eval (~3-5 min incl. first-run lib compile):
docker run --rm --gpus all \
    -e DISPLAY= \
    -v ~/SpatialActor:/workspace/SpatialActor \
    -v ~/spact_ckpt:/workspace/ckpt \
    -v ~/spact_pretrained:/data/ckpt/spact/pretrained \
    -v ~/.cache:/root/.cache \
    spatial_actor:latest \
    bash -c '
        cd /workspace/SpatialActor
        python spatial_actor/eval.py \
            --model-path /workspace/ckpt/model_45.pth \
            --eval-datafolder "" \
            --tasks close_jar \
            --eval-episodes 1 \
            --episode-length 25 \
            --device 0 \
            --headless \
            --save-video \
            --log-name smoke
    '

# Video appears (path depends on whether the model solved the fresh scene):
#   ~/spact_ckpt/eval/smoke/model_45/videos/close_jar/close_jar_success_0.mp4
#   ~/spact_ckpt/eval/smoke/model_45/videos/close_jar/close_jar_fail_0.mp4
```

- `-v ~/spact_pretrained:/data/ckpt/spact/pretrained` is the mount that
  satisfies the checkpoint cfg's `dep_exp_path` — keep it exactly as written.
- `-v ~/.cache:/root/.cache` is optional; it persists CLIP-RN101 (~290 MB) and
  torchvision ResNet-50 (~100 MB) auto-downloads across runs. Drop it and they
  re-download each run.

Expected result: a single ~5-second 320×180 MP4 of the Panda arm attempting to
close the red jar, plus `[Evaluation] Finished close_jar | Final Score: <0 or 100>`
on stdout. Because the demo-bypass uses a **fresh procedural scene**, success on
any single seed is stochastic — run a few episodes (e.g. `--eval-episodes 5`) to
see the agent actually solve it. A pre-rendered sample clip is in
[`examples/`](./examples/).

> **What is PerAct?** PerAct ([Shridhar et al. 2022](https://peract.github.io/))
> is the multi-task manipulation policy whose 100-demos-per-task dataset became
> the de-facto RLBench eval protocol; SpatialActor reports numbers on its
> standard 18-task / 25-eval-seed setup. This guide **skips the dataset
> entirely** (`shihao1895/rlbench`, ~70 GB) and the demo-bypass patch makes
> RLBench fall back to `task.reset()`. So a `Final Score: 100.0` here means "the
> model solved one fresh-seed episode", **not** "matches the paper's reported
> success rate."

---

## Running the full / partial protocol (optional)

To reproduce paper-style numbers you need the real dataset. Download the test
split of [`shihao1895/rlbench`](https://huggingface.co/datasets/shihao1895/rlbench)
to e.g. `~/rlbench_data/test`, mount it, and point `--eval-datafolder` at it
(then the demo-bypass patch is a no-op — real demos are found and loaded):

```bash
docker run --rm --gpus all \
    -e DISPLAY= \
    -v ~/SpatialActor:/workspace/SpatialActor \
    -v ~/spact_ckpt:/workspace/ckpt \
    -v ~/spact_pretrained:/data/ckpt/spact/pretrained \
    -v ~/rlbench_data:/workspace/data \
    -v ~/.cache:/root/.cache \
    spatial_actor:latest \
    bash -c '
        cd /workspace/SpatialActor
        python spatial_actor/eval.py \
            --model-path /workspace/ckpt/model_45.pth \
            --eval-datafolder /workspace/data/test \
            --tasks all \
            --eval-episodes 25 \
            --episode-length 25 \
            --device 0 --headless --log-name rlbench_all
    '
```

The author's published `model_45` scores (in `~/spact_ckpt/eval/rlbench_all/model_45/`)
average ~87.8% across the 18 tasks. Per note in the upstream README, RLBench
eval is stochastic; evaluating several epochs (35/40/45/50) is recommended for a
faithful comparison.

---

## What's inside the image

| Layer | Version |
|---|---|
| Base | `nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04` (CUDA + nvcc, glibc 2.31) |
| Python env | Miniconda env `spact`, Python 3.9 (SpatialActor env spec) |
| Torch | 1.12.1+cu113 / torchvision 0.13.1+cu113 / torchaudio 0.12.1 (pip) |
| CUDA libs | cudatoolkit 11.3 (conda) + devel-base nvcc 11.3 |
| pytorch3d / xformers | 0.7.5 / 0.0.16 (conda binaries, `py39_cu113_pyt1121`) |
| CoppeliaSim | 4.1.0 Edu Ubuntu20.04 build |
| PyRep | `stepjam/PyRep@231a1ac6` (pinned; CoppeliaSim-4.1-compatible) |
| RLBench | `buttomnutstoast/RLBench@587a6a0e6` (pinned, **not** stepjam HEAD) |
| YARR | `NVlabs/YARR@f4aaeea` (**rvt branch** — has `TextSummary`; `main` does not) + single-episode flush patch |
| HF stack | transformers 4.40.1, bitsandbytes 0.38.1, CLIP (OpenAI) |
| Headless | Xvfb :99 started by the entrypoint (when `$DISPLAY` is empty or the bare `:99` default with no X server yet) — works with or without `-e DISPLAY=` |
| Init | `tini` PID 1 |

Final image size: ~25-30 GB on disk (CUDA devel + conda + torch + pytorch3d +
xformers + CoppeliaSim binaries).

SpatialActor itself is **bind-mounted** (`~/SpatialActor → /workspace/SpatialActor`),
not cloned into the image, so host-side edits apply immediately. On first
container start the entrypoint compiles + installs the two in-repo libs
(`third_libs/point-renderer` via `nvcc`, then the `spatial_actor` package) with
`--no-deps`, and marks `/workspace/.spatial_actor_installed`. PyRep / RLBench /
YARR are baked into the image, not installed at runtime.

---

## Patch summary

| Patch | Where applied | File touched | What it does |
|---|---|---|---|
| `01-bypass-demo-loading.patch` | host `~/SpatialActor` (step 3) | `spatial_actor/envs/custom_rlbench_env.py` | `reset_to_demo()` in both env classes falls back to `task.reset()` (variation 0, fresh procedural scene) when no demo dataset is on disk. |
| `02-enable-singleep-summaries.patch` | **baked at build** | `yarr/utils/stat_accumulator.py` (YARR clone) | `_SimpleAccumulator.pop()` flushes when `len(episode_returns) >= 1` (was `> 1`), so 1-episode runs emit scores + a `VideoSummary`. |

Both are safe to re-run under `patch -p1 --forward`: an already-applied patch is
detected and skipped (it does not corrupt the file), though a second run exits
non-zero and drops a `.rej` — so the host step in the TL;DR is a one-time apply.

---

## Pretrained weights this setup downloads

| Component | Source | Used at eval | Notes |
|---|---|---|---|
| SpatialActor checkpoint | model repo [`shihao1895/spact-rlbench`](https://huggingface.co/shihao1895/spact-rlbench) — `model_45.pth` (+ `cfg.yaml`) | yes | The collection page is titled `spatialactor`; the actual checkpoint repo is `spact-rlbench`. `cfg.yaml` MUST sit next to the `.pth` (eval reads it from the model dir). |
| DepthAnythingV2-Base | [`depth-anything/Depth-Anything-V2-Base`](https://huggingface.co/depth-anything/Depth-Anything-V2-Base) — `depth_anything_v2_vitb.pth` | yes | The frozen depth-expert backbone (DINOv2 ViT-B). Mounted at `/data/ckpt/spact/pretrained`. Ungated. |
| CLIP-RN101 | OpenAI CLIP lib (auto-download) | yes | Semantic encoder + text encoder. Cached under `~/.cache/clip`. |
| ResNet-50 (ImageNet) | torchvision (auto-download) | yes | Geometry encoder backbone. Cached under `~/.cache/torch`. |

None require a HuggingFace login — there is no gated PaliGemma/Gemma/LLaMA in
SpatialActor.

---

## Examples

Pre-rendered clips from demo-bypass smoke evals (fresh procedural scenes, not
PerAct-protocol seeds — see the caveat above), all `model_45`, 320×180, each run
scoring 100.0 on its episode:

| Clip | Lang goal |
|---|---|
| [`spatial_actor_close_jar_success.mp4`](./examples/spatial_actor_close_jar_success.mp4) | close the red jar |
| [`spatial_actor_open_drawer_success.mp4`](./examples/spatial_actor_open_drawer_success.mp4) | open the bottom drawer |
| [`spatial_actor_push_buttons_success.mp4`](./examples/spatial_actor_push_buttons_success.mp4) | push the maroon button |
| [`spatial_actor_sweep_to_dustpan_of_size_success.mp4`](./examples/spatial_actor_sweep_to_dustpan_of_size_success.mp4) | sweep dirt to the tall dustpan |
| [`spatial_actor_meat_off_grill_success.mp4`](./examples/spatial_actor_meat_off_grill_success.mp4) | take the chicken off the grill |
| [`spatial_actor_turn_tap_success.mp4`](./examples/spatial_actor_turn_tap_success.mp4) | turn left tap |

These were generated end-to-end by the TL;DR step-7 command (varying `--tasks`)
on an RTX 3060 12 GB (peak GPU memory ~3 GB). Reproduce the whole set with one
container run:

```bash
docker run --rm --gpus all -e DISPLAY= \
    -v ~/SpatialActor:/workspace/SpatialActor \
    -v ~/spact_ckpt:/workspace/ckpt \
    -v ~/spact_pretrained:/data/ckpt/spact/pretrained \
    -v ~/.cache:/root/.cache \
    spatial_actor:latest \
    bash -c '
        cd /workspace/SpatialActor
        python spatial_actor/eval.py \
            --model-path /workspace/ckpt/model_45.pth --eval-datafolder "" \
            --tasks open_drawer push_buttons sweep_to_dustpan_of_size meat_off_grill turn_tap \
            --eval-episodes 3 --episode-length 25 \
            --device 0 --headless --save-video --log-name variety
    '
```

## Known limitations

- **Not the paper protocol.** The smoke run bypasses demo loading, so the scene
  is a fresh procedural sample, not one of PerAct's 25 evaluation seeds. Scores
  here are **not** comparable to SpatialActor's published table. Use the
  [full-protocol section](#running-the-full--partial-protocol-optional) with the
  real dataset for that.
- **First-run compile cost.** The point-renderer CUDA extension compiles on the
  first container start (~1-3 min). The build artifact persists in the host
  bind-mount, so later runs skip recompilation; but because `pip install -e`
  registers into the container's (ephemeral, `--rm`) site-packages, the fast
  re-install step still runs once per fresh container.
- **Root-owned build artifacts in the bind-mount.** The container runs as root,
  so the first-run point-renderer compile writes `third_libs/point-renderer/build/`
  and `point_renderer/_C*.so` into the host `~/SpatialActor` as `root:root`. A
  later `git clean`/`git status` or a non-root rebuild there may trip on them;
  `sudo chown -R $USER ~/SpatialActor` if you need to reclaim them.
- **conda binary URLs.** The build pulls pytorch3d/xformers from
  `anaconda.org/{pytorch3d,xformers}`. If those exact `.tar.bz2` URLs ever move,
  the two `conda install <url>` lines in the Dockerfile must be updated.
- **No public registry push.** CoppeliaSim Edu, RLBench, and SpatialActor all
  have non-redistribution clauses — build the image locally, don't push it to
  Docker Hub or any public registry.
