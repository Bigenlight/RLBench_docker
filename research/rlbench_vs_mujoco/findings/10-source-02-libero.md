# LIBERO — Deep-Dive Findings

**Source:** Liu et al., "LIBERO: Benchmarking Knowledge Transfer for Lifelong Robot Learning", NeurIPS 2023 Datasets & Benchmarks. arXiv:2306.03310.
**Repo inspected:** `LIBERO/` (git clone --depth 1 of https://github.com/Lifelong-Robot-Learning/LIBERO, commit on branch main, 2025-05-21)

---

## 1. Simulator Backend

**Stack:** Robosuite 1.4.0 → MuJoCo (new Python bindings, not mujoco-py).

The `requirements.txt` pins `robosuite==1.4.0`. The base domain directly imports the new
`mujoco` Python package (DeepMind open-source, post-2.1):

```
LIBERO/libero/libero/envs/bddl_base_domain.py:13: import mujoco
```

No version of MuJoCo is pinned explicitly in `requirements.txt`; Robosuite 1.4.0 itself
requires `mujoco>=2.2.0` (newer binding). `mujoco-py` is **not** used.

**Simulation step rate:** `control_freq=20` Hz (default in `ControlEnv`).
`LIBERO/libero/libero/envs/env_wrapper.py:L26: control_freq=20`

**Determinism:** Not guaranteed across runs — `env.seed(seed)` calls `np.random.seed(seed)`
only; MuJoCo physics itself is deterministic given identical initial state; LIBERO provides
fixed pre-sampled initial states (`.pruned_init` files) for reproducible evaluation rollouts.

**Renderer:** `renderer="mujoco"` (default in `ControlEnv`/`BDDLBaseDomain`), using MuJoCo's
native OpenGL EGL backend for offscreen.
`LIBERO/libero/libero/envs/env_wrapper.py:L39: renderer="mujoco"`

---

## 2. Scene Format

**Format: BDDL (Behavior Domain Definition Language) — a PDDL-inspired DSL.**

Each task is a `.bddl` text file that declares:
- `(:language ...)` — the natural-language instruction string for the task
- `(:regions ...)` — named spatial regions with bounding-box ranges and optional yaw rotation
- `(:fixtures ...)` — static/semi-static objects (cabinets, stoves, tables) with types
- `(:objects ...)` — movable objects with types
- `(:obj_of_interest ...)` — which objects are tracked for success checking
- `(:init ...)` — initial placement predicates (`On`, `Open`, `Close`, `TurnOn`, etc.)
- `(:goal ...)` — goal predicate expression (`And`, `On`, etc.)

Example (LIBERO-Spatial task, file `pick_up_the_black_bowl_between_the_plate_and_the_ramekin_and_place_it_on_the_plate.bddl`):
```bddl
(define (problem LIBERO_Tabletop_Manipulation)
  (:domain robosuite)
  (:language Pick the akita black bowl between the plate and the ramekin and place it on the plate)
  ...
  (:goal
    (And (On akita_black_bowl_1 plate_1))
  )
)
```

Tasks are **authored programmatically** via a Python scene-template + BDDL generation
pipeline (see `libero/libero/utils/bddl_generation_utils.py`,
`libero/libero/benchmark/mu_creation.py`). No GUI is involved. The pipeline defines
`InitialSceneTemplates` classes per scene (e.g. `KitchenScene1`) and then generates
`.bddl` files from them. This enables "in principle infinite" task generation
[LIBERO paper §3.1].

**Assets:** Custom MuJoCo MJCF XML assets under `libero/libero/assets/` (objects, arenas,
scenes like `scenes/libero_base_style.xml`). Objects are custom-built for LIBERO (akita
black bowl, moka pot, cookie box, etc.) — not stock MuJoCo XML.

**BDDL version pinned:** `bddl==1.0.1` (requirements.txt:L11)

---

## 3. Rendering

**Backend:** MuJoCo native EGL (GPU-accelerated offscreen). Controlled via environment
variable `MUJOCO_EGL_DEVICE_ID=GPU_ID` (shown in README training command).

**OffscreenRenderEnv:** Primary env class; `has_renderer=False, has_offscreen_renderer=True`.
`LIBERO/libero/libero/envs/env_wrapper.py:L152-L161`

**Cameras:**
- `agentview` — fixed overhead third-person view (canonical robot eye level)
- `robot0_eye_in_hand` — wrist-mounted camera
- `canonical_agentview` — slightly different pose variant
- `frontview` — used in demo collection
Both agentview and eye-in-hand are standard for training/evaluation.
`LIBERO/libero/libero/envs/env_wrapper.py:L31-L35`

**Default image resolution:** `camera_heights=128, camera_widths=128`.
Default in `ControlEnv` (env_wrapper.py:L34-L35) and confirmed in config:
`LIBERO/libero/configs/data/default.yaml:L16-17: img_h: 128 / img_w: 128`
Note: `BDDLBaseDomain` defaults to 256×256 but all training configs use 128×128.

**Vectorized / multiprocess envs:** Natively supported via `SubprocVectorEnv` and
`DummyVectorEnv` (cloudpickle-based subprocess wrappers).
`LIBERO/libero/libero/envs/venv.py`
During evaluation, 20 subprocesses are launched in parallel:
`evaluate.py:L244: env_num = 20`

**Depth / segmentation:** Optional (`camera_depths`, `camera_segmentations`); `SegmentationRenderEnv` available.

---

## 4. Observation and Action Space

### Observations (runtime env keys)
Defined in `BDDLBaseDomain._setup_observables()` and config:

| Key | Content |
|-----|---------|
| `agentview_image` | RGB image 128×128×3 |
| `robot0_eye_in_hand_image` | RGB image 128×128×3 |
| `robot0_gripper_qpos` | gripper joint positions (2-dim) |
| `robot0_joint_pos` | 7-DOF arm joint positions |
| `robot0_eef_pos` | end-effector position (3-dim) |
| `robot0_eef_quat` | end-effector quaternion (4-dim) |
| `{obj_name}_pos`, `{obj_name}_quat`, etc. | per-object state (not used in default policy training) |

Default training config (`data/default.yaml`):
```yaml
obs:
  modality:
    rgb: ["agentview_rgb", "eye_in_hand_rgb"]
    low_dim: ["gripper_states", "joint_states"]
```

### Action Space
**7-DOF OSC_POSE (Operational Space Controller Pose)**: 3 Cartesian position deltas + 3 orientation deltas (axis-angle) + 1 gripper binary. Actions are 7-dimensional.
Default controller: `controller="OSC_POSE"` in `ControlEnv`.
`LIBERO/libero/libero/envs/env_wrapper.py:L17`
The `action_dim==4` fallback in `bddl_base_domain.py:L801` handles `OSC_POSITION` (3+1 gripper).

### HDF5 Demo Data Format
Each task has a file `{task_name}_demo.hdf5` with structure:
```
data/
  demo_0/
    obs/
      agentview_rgb      (T, 128, 128, 3)
      eye_in_hand_rgb    (T, 128, 128, 3)
      gripper_states     (T, 2)
      joint_states       (T, 7)
      ee_states          (T, 6)   # ee_pos (3) + ee_ori axis-angle (3)
    actions              (T, 7)
    states               (T, ?)   # full MuJoCo sim state
    robot_states         (T, 9)   # gripper_qpos(2) + eef_pos(3) + eef_quat(4)
    rewards              (T,)
    dones                (T,)
  demo_1/
    ...
  attrs: num_demos, total, tag="libero-v1"
```
`LIBERO/scripts/create_dataset.py:L236-L270`

**Demos per task:** 50 per task across all suites.
`LIBERO/scripts/check_dataset_integrity.py:L19: if count == 50:`

### Language Annotation
Each task has a single natural-language instruction string embedded in the `.bddl` file
under `(:language ...)`. This string is also accessible as `task.language` at runtime.
The instructions are **template-generated, descriptive sentences** — not free-form annotations.

Examples:
- LIBERO-Spatial: `"Pick the akita black bowl between the plate and the ramekin and place it on the plate"`
- LIBERO-Object: `"pick up the alphabet soup and place it in the basket"`
- LIBERO-Goal: `"open the middle drawer of the cabinet"`
- LIBERO-Long: `"put both the alphabet soup and the tomato sauce in the basket"` (multi-step)

Language embeddings for policy conditioning: default BERT (`bert-base-cased`), also
supports GPT-2, CLIP (`openai/clip-vit-base-patch32`), RoBERTa.
`LIBERO/libero/lifelong/utils.py:L161-L209`

---

## 5. Robot Models

**Default arm:** Franka Panda (7-DOF).
`ControlEnv` default: `robots=["Panda"]`; robosuite `MountedPanda` and `OnTheGroundPanda`
variants are defined in `libero/libero/envs/robots/`.

**Gripper:** PandaGripper (Robosuite default for Panda); 2-finger parallel.

**Contact simulation:** MuJoCo-based (more stable than PyBullet for contact-rich tasks).
Table friction: `(0.6, 0.005, 0.0001)` (tangential, torsional, rolling).
`LIBERO/libero/libero/envs/bddl_base_domain.py:L315`

**Multi-embodiment:** Not supported in the original LIBERO benchmark. Only Panda is used.
No multi-arm, no bimanual tasks in the 130-task suite.

---

## 6. Ecosystem

### VLA / Imitation Learning Papers Benchmarking on LIBERO

**Confirmed (from paper, repo, and LIBERO-PRO 2024 study):**
- **OpenVLA** (Kim et al., 2024, Stanford/Berkeley) — evaluated on all 4 LIBERO suites; fine-tuned checkpoints on HuggingFace (`moojink/openvla-7b-oft-finetuned-libero-*`)
- **π0 / pi0** (Black et al., Physical Intelligence, 2024) — official pi0 LIBERO checkpoint available (pi0.5 also tested in LIBERO-PRO)
- **CogACT** (2024, ~7B) — evaluated on LIBERO [LIBERO-PRO study]
- **Magma** (Microsoft, CVPR 2025) — few-shot finetuning on LIBERO [Microsoft Research blog]
- **RoboFlamingo** (ICLR 2024) — uses LIBERO as one evaluation benchmark
- **MimicPlay** (CoRL 2023) — evaluated on LIBERO [libero-project.github.io/research]
- **MUTEX** (CoRL 2023) — evaluated on LIBERO
- **TAIL** (2023 preprint) — evaluated on LIBERO
- **Diffusion Policy** — used via LeRobot integration (HuggingFace lerobot/libero)

**Not confirmed on LIBERO:** BridgeVLA (not found in search), GR00T N1 (NVIDIA; LIBERO eval mentioned in a GitHub issue but not officially confirmed), Embodied-CoT (not found).

**LIBERO-PRO** (arXiv:2510.03827, Oct 2024) reveals that OpenVLA, π0, π0.5 all achieve ≥90% on standard LIBERO but collapse under perturbations (changed object positions, rephrased instructions).

### HuggingFace Presence
- **Datasets:** `yifengzhu-hf/LIBERO-datasets` (~100 GB, HDF5, 24k+ monthly downloads)
- **LeRobot integration:** LIBERO datasets available in RLDS format via LeRobot
  `https://huggingface.co/docs/lerobot/libero`
- **Pretrained checkpoints:** OpenVLA-OFT fine-tuned on each LIBERO suite (Hugging Face)

---

## 7. Install / Ops

### Install Steps
```bash
conda create -n libero python=3.8.13
conda activate libero
pip install -r requirements.txt
pip install torch==1.11.0+cu113 torchvision==0.12.0+cu113 ...
pip install -e .
```
`LIBERO/README.md:L50-L60`

**Key pinned versions:**
| Package | Version |
|---------|---------|
| Python | 3.8.13 |
| robosuite | 1.4.0 |
| bddl | 1.0.1 |
| robomimic | 0.2.0 |
| PyTorch | 1.11.0+cu113 |
| transformers | 4.21.1 |
| gym | 0.25.2 |

### MuJoCo Licensing
DeepMind open-sourced MuJoCo under Apache 2.0 (October 2021, v2.1.0+). No license fees.
LIBERO itself: MIT (codebase) + CC BY 4.0 (datasets).

### Headless Rendering
Uses `MUJOCO_EGL_DEVICE_ID=GPU_ID` environment variable to route EGL rendering to a
specific GPU. No `DISPLAY` required. No OSMesa needed.
`LIBERO/README.md:L145`

### Docker
No official Docker recipe provided in the repo.

### Common Breakage Points
1. **Old mujoco-py vs new mujoco binding:** LIBERO uses `import mujoco` (new binding).
   Robosuite 1.4.0 requires the new binding. Do not install `mujoco-py`.
2. **PyTorch / CUDA version mismatch:** Pinned to CUDA 11.3. Newer GPUs (Ada Lovelace)
   may require manual upgrade.
3. **transformers==4.21.1** is quite old; newer versions may conflict with model loading.
4. **SubprocVectorEnv + EGL:** Frame buffer conflicts when spawning many subprocess envs
   (the evaluation code retries env creation up to 5 times with a `time.sleep(5)` guard).
5. **bddl==1.0.1** is not on PyPI in newer versions; must match this exact version.

---

## 8. Evaluation Protocol

### Task Suites

| Suite | Tasks | Notes |
|-------|-------|-------|
| LIBERO-Spatial | 10 | Same objects, varying spatial placement; isolates spatial knowledge |
| LIBERO-Object | 10 | Same spatial layout, varying objects; isolates object knowledge |
| LIBERO-Goal | 10 | Same objects+layout, different goal predicates; isolates procedural knowledge |
| LIBERO-90 | 90 | Pretraining corpus for LIBERO-100; entangled knowledge transfer |
| LIBERO-Long (LIBERO-10) | 10 | Long-horizon downstream test tasks for LIBERO-100 lifelong protocol |
| **LIBERO-100** | **100** | LIBERO-90 + LIBERO-10; combined benchmark |

Task counts confirmed by file count: `ls bddl_files/libero_spatial | wc -l = 11` (10 tasks + tasks_info.txt), etc.

**Total: 130 tasks** (10 + 10 + 10 + 90 + 10 with LIBERO-100 being the union of libero_90+libero_10). [LIBERO paper §1]

### Demonstrations Per Task
**50 demos per task** for all suites.
`LIBERO/scripts/check_dataset_integrity.py:L19`

### Evaluation Rollouts
**20 rollouts per task** (default `n_eval=20`).
`LIBERO/libero/configs/eval/default.yaml:L5`
`evaluate.py:L244: env_num = 20`

**Max steps per rollout:** 600 (at 20 Hz = 30 seconds).
`LIBERO/libero/configs/eval/default.yaml:L7`

**Success metric:** Binary episode-level success (1 if goal predicate satisfied before
horizon, 0 otherwise). Success rate = fraction of 20 rollouts that succeed.
`evaluate.py:L284-L288`

### Lifelong Learning Protocol
The primary LIBERO scenario is **sequential task learning** (continual/lifelong IL):
- Policy learns tasks T1, T2, …, T10 sequentially (one suite at a time).
- After learning each new task Tk, the policy is evaluated on ALL previously seen tasks
  T1…Tk to measure forward transfer and backward transfer.
- 21 pre-defined task orderings provided (`task_orders` in `benchmark/__init__.py:L83-L105`)
  for robustness analysis.
- Algorithms: Sequential fine-tuning (base), ER (experience replay), EWC, PackNet, Multitask.

**Metrics:** AUC (area under success rate curve over task sequence), FWT (forward transfer),
NBT (negative backward transfer / forgetting). [LIBERO paper §4 / NeurIPS 2023 review]

### LIBERO-90 → LIBERO-10 Transfer
- Pretrain on LIBERO-90 (90 tasks, 50 demos each = 4500 total demos)
- Lifelong fine-tune on LIBERO-10 (10 long-horizon tasks)
- Measures transfer of entangled knowledge [LIBERO paper §3.3]

---

## Summary: Top 5 Most Distinctive LIBERO Traits Relative to RLBench

1. **BDDL task DSL**: Tasks are defined in a PDDL-inspired text format encoding spatial regions, object types, and goal predicates — enabling programmatic, infinite task generation with zero manual scene scripting (vs. RLBench's Python-coded task classes + CoppelaSim/PyRep scenes).

2. **MuJoCo via Robosuite (new Python binding, free, headless-first)**: Pure EGL GPU offscreen rendering via `MUJOCO_EGL_DEVICE_ID`; no X11 display, no Xvfb/VirtualGL; SubprocVectorEnv for parallelism. RLBench requires CoppeliaSim with complex headless setup.

3. **Lifelong learning protocol with 21 task orderings**: Uniquely designed to measure catastrophic forgetting (NBT), forward transfer (FWT), and AUC over sequential task streams. RLBench has no built-in continual/lifelong protocol.

4. **Native language annotation embedded in task DSL**: Every task has a natural-language goal string in the `.bddl` file (`(:language ...)`), auto-derivable from file name for LIBERO-100, encoded via BERT/CLIP at training time. No separate annotation step required.

5. **De facto VLA benchmark standard (2024–2025)**: OpenVLA, π0, π0.5, CogACT, Magma, and RoboFlamingo all report LIBERO numbers; datasets on HuggingFace with 24k+ monthly downloads and LeRobot integration. RLBench sees far fewer VLA paper evaluations.

---

*Findings grounded in repo inspection of `LIBERO/` (cloned 2025-05-21) and arXiv:2306.03310.*
