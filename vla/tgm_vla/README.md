# TGM-VLA on RLBench — Standalone Docker Eval

Build & run a self-contained container for [TGM-VLA](https://github.com/PuFanqi23/TGM-VLA)
(Task-Goal-Manipulation VLA with SAM2 + custom point-renderer CUDA op) against
RLBench eval, headlessly, on a single mid-range GPU (verified RTX 3060 12 GB),
**without** the 19 GB PerAct demo dataset.

For the directory pattern and how to add a new VLA, see [`vla/README.md`](../README.md).
For the base RLBench Docker setup (different Python / RLBench fork — not
extended here), see [`docker/README.md`](../../docker/README.md). For the
sibling BridgeVLA overlay, see [`vla/bridgevla/README.md`](../bridgevla/README.md).

## Prerequisites (host machine)

Before anything, the host needs:

- **Linux** with an **NVIDIA GPU** (tested: RTX 3060 12 GB, driver 590.x).
  12 GB VRAM is enough for the verified smoke tasks (open_drawer, push_buttons,
  close_jar). Below 8 GB the model OOMs.
- **NVIDIA driver** installed (`nvidia-smi` works on the host).
- **Docker** >= 20.10 (`docker --version`).
- **NVIDIA Container Toolkit** so Docker can see the GPU
  (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
  Verify with:
  ```bash
  docker run --rm --gpus all nvidia/cuda:12.1.1-runtime-ubuntu22.04 nvidia-smi
  ```
  If this prints the GPU table, you're good. If it errors, fix this first
  — the rest of the guide will fail in less obvious ways.
- **Disk**: ~38 GB free (Docker image ~20 GB on disk, TGM-VLA repo + git-lfs
  weights ~6 GB, `model_rlbench.pth` checkpoint ~2 GB, build cache + HF cache
  + headroom ~10 GB).
- **`python3` + `pip`** on the host for the `huggingface_hub` CLI used to
  download the checkpoint. On Ubuntu 23.04+ / Debian 12, `pip` is
  PEP-668-managed and rejects `--user` installs outside a venv — see step 4
  below for the fallback.
- **`git lfs`** on the host (`sudo apt-get install -y git-lfs`) — TGM-VLA
  ships the vendored RLBench fork's `.ttt` / `.ttm` CoppeliaSim scene files
  via Git LFS, and without it the clone in step 2 lands 134-byte text-pointer
  stubs instead of real scenes (failure shows up only deep inside CoppeliaSim
  as a scene-corruption error).

You do **not** need: CoppeliaSim on the host, PyTorch on the host, the
RLBench fork installed on the host, the PerAct test dataset. Everything is
inside the container, and demo data is generated locally (see [Demo data](#demo-data)).

> **Note**: Building `docker/Dockerfile` (the plain-RLBench dev image) is
> NOT needed for TGM-VLA eval. Only the `vla/tgm_vla/Dockerfile` below.

---

## TL;DR

```bash
# 0. Clone THIS repo (the one you're reading this README from):
git clone https://github.com/Bigenlight/RLBench_docker.git
cd RLBench_docker
REPO_ROOT=$(pwd)   # remember it for step 3

# 1. Build the TGM-VLA Docker image (~25-35 min cold; ~10 sec when cached):
docker build -t tgmvla:latest \
    --build-arg ACCEPT_TGMVLA_LICENCE=YES \
    -f vla/tgm_vla/Dockerfile .

# > If the build fails downloading CoppeliaSim 4.1.0 Edu (URL dead or
# > network blocked), the official archive is at
# > https://www.coppeliarobotics.com/previousVersions — grab
# > `CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz` manually, then edit
# > `vla/tgm_vla/Dockerfile` to `COPY` the local tarball instead of `wget`.

# 2. Clone TGM-VLA upstream + pull Git LFS scene files (will be bind-mounted).
#    `command -v git-lfs` guard fails fast if git-lfs is missing — without it,
#    the clone silently lands LFS-pointer text stubs instead of real .ttt
#    scenes and CoppeliaSim fails much later with a cryptic scene-load error.
command -v git-lfs >/dev/null || { echo "install git-lfs first: apt-get install git-lfs"; exit 1; }
git clone https://github.com/PuFanqi23/TGM-VLA.git ~/TGM-VLA
cd ~/TGM-VLA
git lfs install
git lfs pull
cd -

# 3. Patches are applied AUTOMATICALLY by the container's entrypoint on
#    first run (with `patch -N` so re-runs are idempotent), so this step is
#    OPTIONAL on the host. Apply locally only if you want to inspect or
#    iterate on the patched code:
#
# cd ~/TGM-VLA
# PATCH_DIR="${REPO_ROOT}/vla/tgm_vla/patches"
# patch -p1 --forward < "$PATCH_DIR/01-eval-video-save.patch"
# patch -p1 --forward < "$PATCH_DIR/02-task-score-fallback.patch"
# patch -p1 --forward < "$PATCH_DIR/03-disable-redundant-video-block.patch"
# cd -

# 4. Install huggingface_hub CLI on the host (one-time, ~10 MB).
#    On Ubuntu 23.04+ / Debian 12 the system pip is PEP-668-managed and
#    rejects `--user`. Use a venv (preferred) or `--break-system-packages`:
python3 -m pip install --user huggingface_hub 2>/dev/null || \
    python3 -m pip install --user --break-system-packages huggingface_hub || {
        # Fallback: an isolated venv
        python3 -m venv ~/.tgmvla_venv
        ~/.tgmvla_venv/bin/pip install huggingface_hub
        export PATH="$HOME/.tgmvla_venv/bin:$PATH"
    }
# Make sure `~/.local/bin` is on PATH (where `--user` installs land).
export PATH="$HOME/.local/bin:$PATH"

# 5. Download the RLBench fine-tune checkpoint (~1.97 GB) into the TGM-VLA repo.
#    SAM2 is NOT downloaded here — it is baked into the image at
#    /opt/sam2_ckpts/sam2.1_hiera_base_plus.pt (~309 MB) and symlinked into
#    place by the entrypoint on first container start.
#    `huggingface-cli` is the legacy CLI shipped by every huggingface_hub
#    release; `hf` is the newer alias (>=0.19) — using `huggingface-cli` is
#    the most portable form.
mkdir -p ~/TGM-VLA/runs/tgmvla_test
huggingface-cli download FanqiPu/TGM-VLA model_rlbench.pth \
    --local-dir ~/TGM-VLA/runs/tgmvla_test

# 6. Confirm the checkpoint landed:
ls -lh ~/TGM-VLA/runs/tgmvla_test/model_rlbench.pth
# expected: ~1.97 GB

# 7. Generate ~1 episode of demo data per task (~10 sec/episode), then run a
#    1-episode open_drawer smoke eval. First container start does the
#    `pip install -e` of TGM-VLA's vendored libs (~2-3 min, compiles
#    point-renderer's CUDA op); subsequent starts skip it.
#
# Pre-create the HF cache so Docker doesn't auto-create it as root-owned, and
# pass `--user` so files written into the bind-mount stay editable on the host.
# HOME is pointed at the HF cache dir so CLIP/matplotlib can write their
# small caches (~/.cache/clip, ~/.config/matplotlib) without root privileges.
mkdir -p ~/.cache/huggingface
docker run --rm --gpus all \
    --user "$(id -u):$(id -g)" \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e HOME=/workspace/hf_cache \
    -v "$HOME/TGM-VLA:/workspace/TGM-VLA" \
    -v "$HOME/.cache/huggingface:/workspace/hf_cache" \
    tgmvla:latest \
    bash -c '
        # ---- demo data (skip if already generated) ----
        mkdir -p /workspace/TGM-VLA/data/rlbench/test
        cd /workspace/TGM-VLA/tgm_vla/libs/RLBench
        python tools/dataset_generator.py \
            --save_path /workspace/TGM-VLA/data/rlbench/test \
            --tasks open_drawer,push_buttons,close_jar \
            --image_size 128,128 \
            --renderer opengl3 \
            --episodes_per_task 1 \
            --variations 1 \
            --processes 1 \
            --all_variations

        # ---- eval (absolute paths — test_rlbench.py is under tgm_vla/, NOT
        # at the repo root, so cwd is the tgm_vla/ subdir and we point
        # --model-folder at where step 5 dropped the checkpoint) ----
        cd /workspace/TGM-VLA/tgm_vla
        python tools/test_rlbench.py \
            --model-folder /workspace/TGM-VLA/runs/tgmvla_test \
            --model-name model_rlbench.pth \
            --eval-datafolder /workspace/TGM-VLA/data/rlbench/test \
            --tasks open_drawer \
            --eval-episodes 1 \
            --start-episode 0 \
            --episode-length 25 \
            --log-name smoke_test \
            --device 0 \
            --headless \
            --save-video
    '

# Video appears at:
#   ~/TGM-VLA/runs/tgmvla_test/smoke_test/model_rlbench/videos/open_drawer_success_ep0.mp4
```

Expected result on the verified smoke tasks (RTX 3060 12 GB):

| Task | Steps | Score |
|---|---|---|
| `open_drawer` | 3 | 100 |
| `push_buttons` | 4 | 100 |
| `close_jar` | 5 | 100 |

Pre-rendered clips are in [`examples/smoke/`](./examples/smoke/).

> **What is PerAct?** PerAct ([Shridhar et al. 2022](https://peract.github.io/))
> is the multi-task manipulation VLA whose 100-demos-per-task dataset became
> the de-facto RLBench eval protocol. TGM-VLA's paper reports numbers on
> PerAct's standard 18-task / 25-eval-seeds setup. This guide **skips the
> 19 GB PerAct dataset entirely** and uses RLBench's own `dataset_generator.py`
> to synthesize one fresh procedural episode per task. Score 100 here means
> "the model solved one fresh-seed episode," not "matches the paper's
> reported success rate."

---

## What's inside the image

| Layer | Version |
|---|---|
| Base | `nvidia/cuda:12.1.1-runtime-ubuntu22.04` + `cuda-{nvcc,cudart,libraries}-dev-12-1` |
| Python | 3.10 (Ubuntu 22.04 native; TGM-VLA env spec) |
| CoppeliaSim | 4.1.0 Edu Ubuntu20.04 build |
| PyRep | TGM-VLA vendored fork at `tgm_vla/libs/PyRep` |
| RLBench | TGM-VLA vendored PerAct-style fork at `tgm_vla/libs/RLBench` |
| Torch | 2.1.0 cu121 + torchvision 0.16.0 + pytorch3d 0.7.5 (prebuilt wheel) |
| HF stack | transformers 4.49.0, hydra-core 1.3.2, bitsandbytes 0.38.1, CLIP (OpenAI) |
| SAM2 ckpt | `sam2.1_hiera_base_plus.pt` baked at `/opt/sam2_ckpts/` (~309 MB) |
| NumPy | pinned to 1.26.4 (torch 2.1.0 was compiled against NumPy 1.x ABI) |
| OpenCV | `opencv-python-headless==4.11.0.86` (non-headless build is uninstalled at first start — fights Qt under Xvfb) |
| Headless | Xvfb :99 on demand; `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` |
| Init | `tini` PID 1 |

Final image size: ~18 GB on disk uncompressed (CUDA runtime+dev, PyTorch +
pytorch3d, CoppeliaSim 4.1.0 Edu binaries, baked SAM2 ckpt). For total
disk budgeting (image + repo + LFS + checkpoint) see
[Prerequisites](#prerequisites-host-machine) above.

TGM-VLA itself is **bind-mounted** (`~/TGM-VLA → /workspace/TGM-VLA`),
not cloned into the image, so user-side edits apply immediately. On first
container start the entrypoint runs `pip install --no-deps -e` on six
vendored libs (`RLBench`, `robot-colosseum`, `YARR`, `peract_colab`, `PyRep`,
`point-renderer`) plus the main `tgm_vla` package, then symlinks the baked-in
SAM2 checkpoint into `tgm_vla/network/sam2_train/checkpoints/`.
Subsequent starts detect the install via `import rlbench, pyrep,
point_renderer, tgm_vla` and skip the step (so re-builds of the image
re-install cleanly, even with the same bind-mount source tree).
`point-renderer` compiles a custom CUDA extension during the first install.

---

## Demo data

The 19 GB PerAct test dataset is **not** required. RLBench's own
`dataset_generator.py` synthesizes fresh procedural episodes (~40 MB per
task per episode, ~10 sec wall time). Run inside the container:

```bash
cd /workspace/TGM-VLA/tgm_vla/libs/RLBench
mkdir -p /workspace/TGM-VLA/data/rlbench/test
python tools/dataset_generator.py \
    --save_path /workspace/TGM-VLA/data/rlbench/test \
    --tasks open_drawer,push_buttons,close_jar \
    --image_size 128,128 \
    --renderer opengl3 \
    --episodes_per_task 1 \
    --variations 1 \
    --processes 1 \
    --all_variations
```

Notes:

- `--image_size 128,128` matches TGM-VLA's eval input resolution.
- `--all_variations` makes the generator enumerate every task variation
  RLBench knows about (TGM-VLA's eval loop expects the per-variation
  directory layout, not a single-variation flat dump).
- `--processes 1` is fine for 1 episode each; bump for bigger sweeps.
- Output layout is the standard PerAct-style tree
  (`<task>/all_variations/episodes/episode<N>/...`), which is what
  `--eval-datafolder ../data/rlbench/test` resolves to.

---

## Patches applied

Three patches live under [`patches/`](./patches/), all targeting
`tgm_vla/tools/test_rlbench.py`. The container's `entrypoint.sh` applies
them automatically with `patch -p1 -N` on first run (idempotent — host-side
manual application is also safe):

| Patch | What it does |
|---|---|
| `01-eval-video-save.patch` | Fixes `--save-video`. Upstream's YARR `stats_accumulator` drops the first task's `VideoSummary` before `test_rlbench.py` consumes it, so the flag silently produced no mp4. Patch wires the flag through to `Rollout.record_enabled` and writes the video directly from each episode's `summaries` list via OpenCV. Output goes to `<log_dir>/videos/<task>_<success\|fail>_ep<N>.mp4`. |
| `02-task-score-fallback.patch` | Fixes a `sum()`-of-`"unknown"` crash. When `stats_accumulator` is empty (e.g. small eval, single episode), upstream falls back to the string `"unknown"` for `task_score`, which then explodes in the outer CSV/sum reporting. Patch falls back to `mean(task_rewards)` (or `0.0` if no rewards) so the eval finishes cleanly. |
| `03-disable-redundant-video-block.patch` | Disables upstream's second video-save block inside `save_results`, which indexes `task_rewards[video_cnt]` 1-to-1 against `VideoSummary` objects coming from YARR's cross-task accumulator and `IndexError`s as soon as a second task runs. Patch 01 already saves the videos correctly, so this block becomes redundant. |

---

## Examples

Pre-rendered successful eval clips (Score 100, fresh procedural scenes generated
by `dataset_generator.py` — not PerAct-protocol numbers):

- [`examples/smoke/open_drawer_success_ep0.mp4`](./examples/smoke/open_drawer_success_ep0.mp4)
- [`examples/smoke/push_buttons_success_ep0.mp4`](./examples/smoke/push_buttons_success_ep0.mp4)
- [`examples/smoke/close_jar_success_ep0.mp4`](./examples/smoke/close_jar_success_ep0.mp4)

---

## License

Building and running this image requires accepting **three** licences. The
`ACCEPT_TGMVLA_LICENCE=YES` build arg gates all three:

1. **RLBench** (Imperial College London) — academic / non-commercial use.
   https://github.com/stepjam/RLBench/blob/master/LICENSE
2. **CoppeliaSim Edu** — educational entities only, non-commercial.
   https://manual.coppeliarobotics.com/en/licensing.htm
3. **TGM-VLA** — see the upstream repo LICENSE at
   https://github.com/PuFanqi23/TGM-VLA.

**Do not push the built image to a public registry.** All three components
have non-redistribution clauses. Build locally per host.

---

## Acknowledgements

- [TGM-VLA](https://github.com/PuFanqi23/TGM-VLA) — Pu et al., upstream model
  + vendored RLBench/PyRep/YARR/peract_colab/robot-colosseum/point-renderer
  forks. Checkpoint mirrored at HuggingFace `FanqiPu/TGM-VLA`.
- [RLBench](https://github.com/stepjam/RLBench) — Imperial College London,
  the underlying task suite.
- [CoppeliaSim](https://www.coppeliarobotics.com/) — Coppelia Robotics,
  the simulator that backs RLBench via PyRep.
- [Segment Anything 2](https://github.com/facebookresearch/sam2) — Meta AI,
  source of the `sam2.1_hiera_base_plus.pt` image encoder baked into the
  image.
- [PerAct](https://peract.github.io/) — Shridhar et al., the standard 18-task
  RLBench eval protocol whose layout `dataset_generator.py` reproduces.
