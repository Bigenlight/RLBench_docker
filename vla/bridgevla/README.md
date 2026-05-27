# BridgeVLA on RLBench — Standalone Docker Eval

Build & run a self-contained container for [BridgeVLA](https://github.com/BridgeVLA/BridgeVLA)
(NeurIPS 2025 — 3D VLA on PaliGemma-3B) against RLBench eval, headlessly, on
a single mid-range GPU (verified RTX 3060 12 GB), **without** the official
PerAct demo dataset.

This is the first VLA overlay under [`vla/`](../). For the directory pattern
and how to add a new VLA, see [`vla/README.md`](../README.md). For the base
RLBench Docker setup (different Python / RLBench fork — not extended here),
see [`docker/README.md`](../../docker/README.md).

## Prerequisites (host machine)

Before anything, the host needs:

- **Linux** with an **NVIDIA GPU** (tested: RTX 3060 12 GB, driver 590.x).
  12 GB VRAM is the minimum; below that the model OOMs even with chunking.
- **NVIDIA driver** installed (`nvidia-smi` works on the host).
- **Docker** ≥ 20.10 (`docker --version`).
- **NVIDIA Container Toolkit** so Docker can see the GPU
  (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
  Verify with:
  ```bash
  docker run --rm --gpus all nvidia/cuda:12.1.1-runtime-ubuntu22.04 nvidia-smi
  ```
  If this prints the GPU table, you're good. If it errors, fix this first
  — the rest of the guide will fail in less obvious ways.
- **Disk**: ~50 GB free (Docker image ~27 GB on disk, BridgeVLA checkpoint
  ~7.5 GB, BridgeVLA repo + HF cache ~5 GB, build cache + headroom ~10 GB).
- **`python3` + `pip`** on the host for the `huggingface_hub` CLI used to
  download the checkpoint.

You do **not** need: CoppeliaSim on the host, PyTorch on the host, the
RLBench fork installed on the host. Everything is inside the container.

> **Note**: Building `docker/Dockerfile` (the plain-RLBench dev image) is
> NOT needed for BridgeVLA eval. Only the `vla/bridgevla/Dockerfile` below.

## The non-obvious bits this setup solves

1. **CoppeliaSim headless Qt5 plugin** — `QT_PLUGIN_PATH=$COPPELIASIM_ROOT`,
   the same discovery as the base `docker/Dockerfile` (see its README for the
   full root-cause writeup).
2. **HF-gated PaliGemma** — bypassed via the ungated
   `fal/paligemma-3b-mix-224` config + tokenizer. The BridgeVLA RLBench
   fine-tune checkpoint (`model_80.pth`) already carries the 604 PaliGemma
   weight tensors, so we only need the architecture, not the gated weights.
3. **12 GB VRAM ceiling** — BridgeVLA's `point-renderer.rvt_ops.select_feat_*`
   functions allocated ~2 GiB intermediate int64 tensors. Patched to chunk
   along the `npt` axis (peak drops to ~200 MB).
4. **No PerAct demo dataset** — patched `CustomMultiTaskRLBenchEnv2.reset_to_demo`
   to fall back to `task.reset()` (fresh procedural scene) when
   `dataset_root` is empty. Reproducibility against paper numbers is lost,
   but the eval pipeline runs end-to-end.
5. **TF / LLVM clash** — BridgeVLA's `setup.py` lists `tensorflow` as a dep,
   which bundles its own LLVM and segfaults CoppeliaSim. Uninstalled at
   container start (`tensorboard` is kept, which is what
   `torch.utils.tensorboard` actually needs).
6. **YARR single-episode flush** — `_SimpleAccumulator.pop()` originally
   needed `> 1` episode to emit summaries; relaxed to `>= 1` so an
   `--eval-episodes 1` smoke test still produces a VideoSummary.

> Why this overlay is fully self-contained (no `FROM rlbench-base:latest`):
> BridgeVLA pins **Python 3.9** and the **`buttomnutstoast/RLBench@587a6a0e6`**
> fork, while the base `docker/Dockerfile` uses **Python 3.8** and this repo's
> own RLBench HEAD. The two cannot share an image cleanly, so each VLA folder
> builds its own image from `nvidia/cuda:...` directly. The shared *pattern*
> (CoppeliaSim install, Qt env, Xvfb entrypoint) is documented in
> [`vla/README.md`](../README.md).

---

## TL;DR

```bash
# 0. Clone THIS repo (the one you're reading this README from):
git clone https://github.com/Bigenlight/RLBench_docker.git
cd RLBench_docker
REPO_ROOT=$(pwd)   # remember it for step 3

# 1. Build the BridgeVLA Docker image (~30-40 min cold; ~10 sec when cached):
docker build -t bridgevla:latest \
    --build-arg ACCEPT_BRIDGEVLA_LICENCE=YES \
    -f vla/bridgevla/Dockerfile .

# > If the build fails downloading CoppeliaSim 4.1.0 Edu (URL dead or
# > network blocked), the official archive is at
# > https://www.coppeliarobotics.com/previousVersions — grab
# > `CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz` manually, then edit
# > `vla/bridgevla/Dockerfile` to `COPY` the local tarball instead of `wget`.

# 2. Clone BridgeVLA upstream (will be bind-mounted into the container):
git clone https://github.com/BridgeVLA/BridgeVLA.git ~/BridgeVLA

# 3. Apply the 4 patches to ~/BridgeVLA (one-time, idempotent via --forward):
cd ~/BridgeVLA/finetune
PATCH_DIR="${REPO_ROOT}/vla/bridgevla/patches"
patch -p1 --forward < "$PATCH_DIR/bypass_demo_loading.patch"
patch -p1 --forward < "$PATCH_DIR/bypass_paligemma_auth.patch"
patch -p1 --forward < "$PATCH_DIR/chunk_select_feat_from_hm.patch"
patch -p1 --forward < "$PATCH_DIR/enable_singleep_summaries.patch"
cd -

# Quick sanity check that all 4 patches landed:
grep -q "BRIDGEVLA_RVT_CHUNK" ~/BridgeVLA/finetune/bridgevla/libs/point-renderer/point_renderer/rvt_ops.py \
    && grep -q "fal/paligemma-3b-mix-224" ~/BridgeVLA/finetune/bridgevla/mvt/mvt_single.py \
    && grep -q ">= 1" ~/BridgeVLA/finetune/bridgevla/libs/YARR/yarr/utils/stat_accumulator.py \
    && grep -q "task.reset()" ~/BridgeVLA/finetune/RLBench/utils/custom_rlbench_env.py \
    && echo "All 4 patches applied ✓" || echo "Some patches did NOT apply — re-check the patch outputs above"

# 4. Install huggingface_hub CLI on the host (one-time, ~10 MB):
pip install --user huggingface_hub
# Recent huggingface_hub (>=0.19) exposes `hf` as the primary CLI; older
# installs expose only `huggingface-cli` — swap the command in step 5 if so.

# 5. Pre-create the bind-mount target dirs so Docker doesn't create them as root,
#    then download checkpoint (~7.5 GB, no HF login required — on HF datasets):
mkdir -p ~/.cache/huggingface ~/bridgevla_ckpt
hf download LPY/BridgeVLA --repo-type dataset \
    --include "checkpoints/RLBench/*" --local-dir ~/bridgevla_ckpt

# 6. (Optional) Confirm ~/bridgevla_ckpt/checkpoints/RLBench/mvt_cfg.yaml has
#    `stage_two: true` and `use_point_renderer: true`. Those are already the
#    upstream defaults, so no edit is needed unless you previously overrode them.
#    The chunking patches handle the 12 GB VRAM ceiling at these settings.

# 7. Run 1-episode close_jar eval (~3-4 min including container-start lib install):
docker run --rm --gpus all \
    -e DISPLAY= \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    -e BRIDGEVLA_RVT_CHUNK=300000 \
    -v ~/BridgeVLA:/workspace/BridgeVLA \
    -v ~/.cache/huggingface:/workspace/hf_cache \
    -v ~/bridgevla_ckpt:/workspace/ckpt \
    bridgevla:latest \
    bash -c '
        pip uninstall -y tensorflow >/dev/null
        cd /workspace/BridgeVLA/finetune/RLBench
        python3 eval.py \
            --model-folder /workspace/ckpt/checkpoints/RLBench \
            --eval-datafolder "" \
            --tasks close_jar \
            --eval-episodes 1 \
            --episode-length 25 \
            --log-name run \
            --device 0 \
            --model-name model_80.pth \
            --save-video
    '

# Video appears at one of these paths (depending on whether the model solved it):
#   ~/bridgevla_ckpt/checkpoints/RLBench/eval/run/model_80/videos/close_the_red_jar_success_0.mp4   (success)
#   ~/bridgevla_ckpt/checkpoints/RLBench/eval/run/model_80/videos/close_the_red_jar_failure_0.mp4   (failure)
```

Expected result: a single ~5-second 320×180 MP4 of the Panda arm closing the
red jar, plus `Final Score: 100.0` printed to stdout. Pre-rendered samples
are in [`examples/`](./examples/).

> **What is PerAct?** PerAct ([Shridhar et al. 2022](https://peract.github.io/))
> is the multi-task manipulation VLA whose 100-demos-per-task dataset became
> the de-facto RLBench eval protocol. BridgeVLA's paper reports numbers on
> PerAct's standard 18-task / 25-eval-seeds setup. This guide **skips the
> dataset entirely** (it's >100 GB and not needed if you only want to verify
> the pipeline runs); the `bypass_demo_loading` patch makes RLBench fall back
> to `task.reset()` (fresh procedural scene) so eval still executes. So our
> `Final Score: 100.0` here means "the model solved one fresh-seed episode",
> not "matches the paper's reported success rate."

---

## What's inside the image

| Layer | Version |
|---|---|
| Base | `nvidia/cuda:12.1.1-runtime-ubuntu22.04` + `cuda-{nvcc,cudart,libraries}-dev-12-1` |
| Python | 3.9 (deadsnakes PPA; BridgeVLA env spec) |
| CoppeliaSim | 4.1.0 Edu Ubuntu20.04 build |
| PyRep | `stepjam/PyRep@231a1ac6` (BridgeVLA pin) |
| RLBench | `buttomnutstoast/RLBench@587a6a0e6` (BridgeVLA pin, **not** stepjam HEAD) |
| Torch | 2.5.1 + xformers cu121 + pytorch3d@stable |
| HF stack | transformers 4.51.3, accelerate ≥ 0.26, CLIP (OpenAI) |
| Headless | Xvfb :99 on demand (no DISPLAY env in the image; entrypoint sets it) |
| Init | `tini` PID 1 |

Final image size: ~27 GB on disk (uncompressed, including CUDA dev headers,
PyTorch + xformers + pytorch3d, and CoppeliaSim binaries). For total
disk budgeting (image + checkpoint + repos + build cache) see
[Prerequisites](#prerequisites-host-machine) above.

BridgeVLA itself is **bind-mounted** (`~/BridgeVLA → /workspace/BridgeVLA`),
not cloned into the image, so user-side edits to BridgeVLA source apply
immediately. On first container start the entrypoint runs
`pip install --no-deps -e` on three vendored libs (`YARR`, `peract_colab`,
`point-renderer`) plus the main `bridgevla` package, and marks
`/workspace/.bridgevla_libs_installed` so subsequent starts skip the install.

---

## Patch summary

All four patches live under [`patches/`](./patches/) and are idempotent
(apply with `patch -p1 --forward`):

| Patch | File touched | What it does |
|---|---|---|
| `bypass_demo_loading.patch` | `RLBench/utils/custom_rlbench_env.py` | `reset_to_demo()` falls back to `task.reset()` when `dataset_root` is empty (no demos needed). Uses variation 0. |
| `bypass_paligemma_auth.patch` | `bridgevla/mvt/mvt_single.py` | Switches `model_id` to ungated `fal/paligemma-3b-mix-224`. Constructs `PaliGemmaForConditionalGeneration` from config only (no weight download); the fine-tune ckpt supplies all 604 weights. Skips BridgeVLA pretrain safetensors load when its path is missing. |
| `chunk_select_feat_from_hm.patch` | `bridgevla/libs/point-renderer/point_renderer/rvt_ops.py` | Chunks `select_feat_from_hm` and `select_feat_from_hm_cache` along `npt`. Outputs pre-allocated, written in place — no `torch.cat` peak. Tunable via `BRIDGEVLA_RVT_CHUNK` (default 500_000; we set 300_000 in the example). |
| `enable_singleep_summaries.patch` | `bridgevla/libs/YARR/yarr/utils/stat_accumulator.py` | `_SimpleAccumulator.pop()` now flushes summaries when `len(episode_returns) >= 1` (was `> 1`), so 1-episode runs emit scores + VideoSummary. |

---

## Examples

Pre-rendered successful eval clips (Score 100, fresh procedural scenes via
the demo-bypass patch — not PerAct-protocol numbers):

- [`examples/bridgevla_close_jar_success.mp4`](./examples/bridgevla_close_jar_success.mp4)
- [`examples/bridgevla_open_drawer.mp4`](./examples/bridgevla_open_drawer.mp4)
- [`examples/bridgevla_push_buttons.mp4`](./examples/bridgevla_push_buttons.mp4)
- [`examples/bridgevla_reach_and_drag.mp4`](./examples/bridgevla_reach_and_drag.mp4)

For comparison, [`examples/expert_demo/`](./examples/expert_demo/) holds the
RLBench algorithmic-expert demo of the same close_jar task — i.e. what an
in-distribution learner is supposed to imitate (front + wrist cameras).

---

## Known limitations

- **Not the paper protocol.** We bypass demo loading, so the close_jar scene
  is a fresh procedural sample, not one of PerAct's 25 evaluation seeds. Score
  numbers here are **not** comparable to BridgeVLA's published table.
- **PaliGemma config from the `mix` variant.** `fal/paligemma-3b-mix-224`
  carries the same Gemma tokenizer and same architecture as
  `google/paligemma-3b-pt-224`, but if you ever want to load the gated google
  weights as a base (e.g. for a comparison run), the patch needs to be
  reverted.
- **TF uninstall at container start** is a workaround for the LLVM clash. If
  some downstream BridgeVLA tooling truly needs TF, the workaround needs
  rethinking.
- **Memory headroom is tight.** Close other GPU consumers (browser tabs, IDE)
  before running. With ~1 GiB host VRAM used (Xorg + DE), the model fits,
  but not by much — if you OOM, drop `BRIDGEVLA_RVT_CHUNK` further.
- **No public registry push.** CoppeliaSim Edu, RLBench, and BridgeVLA all
  have non-redistribution clauses — build the image locally, don't push it
  to Docker Hub or any public registry.
