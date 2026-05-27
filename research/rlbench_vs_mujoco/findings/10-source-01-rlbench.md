# Source 01 — RLBench: Facts Extraction

**Source type:** Official paper + GitHub repo (local clone) + Docker ops notes  
**Paper:** James et al., "RLBench: The Robot Learning Benchmark & Learning Environment," IEEE RA-L 2020, arXiv:1909.12271  
**Repo:** https://github.com/stepjam/RLBench (cloned at `/home/theo_lab/RLBench_docker`)  
**Version extracted:** v1.2.0 (`rlbench/__init__.py:L1`), branch `docker/standalone-setup`  
**Date extracted:** 2026-05-21

---

## 1. simulator_backend

**Simulator:** CoppeliaSim (formerly V-REP), version **4.1.0 Edu** is the pinned and only supported version.  
- `docker/Dockerfile:L127`: `wget .../CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz` — hard-coded 4.1.0 download.  
- `docker/README.md:L63`: "CoppeliaSim | **4.1.0 Edu** Ubuntu20.04 build (PyRep/RLBench pin this; newer = segfault)"  
- `README.md:L72`: "RLBench is built around CoppeliaSim v4.1.0 and PyRep"  

**Physics engines:** CoppeliaSim 4.1.0 ships five physics engines — **Bullet, ODE, Vortex, Newton, and MuJoCo** — selectable per scene. (https://manual.coppeliarobotics.com/en/dynamicsModule.htm "supports five different physics engines"). Newton uses "a deterministic solver, which is not based on traditional LCP or iterative methods." The other engines (Bullet, ODE) are non-deterministic across platforms in general. The default engine in use for RLBench tasks is not explicitly set in the Python layer — it is embedded in the `.ttt` scene file (`rlbench/task_design.ttt`). Not stated in Python source.

**Simulation step rate:** `_DT = 0.05` seconds per step (20 Hz control loop) declared in `rlbench/task_environment.py:L18`. The CoppeliaSim UI documentation recommends 50 ms default simulation dt (20 Hz) with 5 ms dynamics sub-steps (200 Hz dynamics). `rlbench/backend/scene.py:L22`: `STEPS_BEFORE_EPISODE_START = 10` (10 warmup steps before episode begins).

**Reported simulation speed (steps/s):** Not stated in paper or repo. The example `examples/rlbench_gym_vector.py` has a `benchmark_vector_step` function that measures FPS empirically at runtime (`rlbench_gym_vector.py:L6-L28`), but no pre-measured numbers are committed.

**Determinism:** Not stated explicitly. CoppeliaSim physics is generally non-deterministic across hardware/OS due to floating-point differences. `Demo.restore_state()` only restores `np.random` state (`rlbench/demo.py:L19-L20`), not the full CoppeliaSim physics state. No documented seed for the physics engine.

**Headless support:** Yes, via Xvfb (X virtual framebuffer). No native offscreen rendering path. The `Environment(headless=True)` flag is passed to `PyRep.launch()` (`rlbench/environment.py:L101`). In practice, CoppeliaSim still needs an X display (real or virtual). See §7 (install_ops) for the full headless story.

---

## 2. scene_format

**Scene file formats:**
- **`.ttt`** — the master CoppeliaSim scene file. One file: `rlbench/task_design.ttt`. This is the base scene (robot, table, cameras). Loaded by `PyRep.launch()` at startup. `rlbench/backend/const.py:L25`: `TTT_FILE = 'task_design.ttt'`.
- **`.ttm`** — CoppeliaSim model files, one per task object set. Stored in `rlbench/task_ttms/` (106 files). Also one per robot arm in `rlbench/robot_ttms/` (panda, jaco, mico, sawyer, ur5). `rlbench/backend/task.py:L305-L311` shows the load sequence: `pyrep.import_model(ttm_file)`.

**Task authoring system:** Each task requires **two files** (`README.md:L382-L386`):
1. A `.ttm` model file (visual/collision geometry + waypoint Dummies) — must be created or edited inside the **CoppeliaSim GUI** (the task builder tool).
2. A `.py` Python class (subclasses `Task`) that wires objects, defines `init_episode(index)` returning NL description strings, defines `variation_count()`, and registers success conditions.

**Template system:** `rlbench/task_design.ttt` is the shared base scene. Task `.ttm` files are dynamically imported at runtime via `pyrep.import_model()`. Waypoints are CoppeliaSim `Dummy` objects named `waypoint0`, `waypoint1`, … embedded in the `.ttm` file. Gripper commands are encoded as string extensions on waypoints (`ext` field): `'open_gripper()'` or `'close_gripper()'` parsed at `rlbench/backend/scene.py:L383-L431`.

**Customization barrier:** Adding a new task requires opening the **CoppeliaSim GUI** to create or modify the `.ttm` file and place waypoints. This is explicitly confirmed by `README.md:L380`: "The task building tool is the interface for users who wish to create new tasks." Video tutorial series is provided. The GUI requirement is a hard constraint — no programmatic scene-only API exists to create `.ttm` files without touching CoppeliaSim.

---

## 3. rendering

**Renderer:** OpenGL via CoppeliaSim's bundled Qt5 + XCB platform plugin. Default render mode is `RenderMode.OPENGL3` (high-quality plugin renderer) per `rlbench/observation_config.py:L14`. An older `RenderMode.OPENGL` (built-in renderer) also works.

**GPU acceleration story:** Complex. CoppeliaSim's OpenGL3 renderer (`libsimExtOpenGL3Renderer.so`) requires a usable GLX context. The key discovery documented in `docker/README.md:L75-L168`:
- **Standard headless guide** (nvidia-xconfig + `sudo X :99`) requires root, modifies host X config, and is cluster-unfriendly.
- **Docker/Xvfb path** uses software GLX (Xvfb) + a single env var fix: `ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}` (`docker/Dockerfile:L172`). Without this, CoppeliaSim's Qt5 xcb plugin cannot locate `xcbglintegrations/libqxcb-glx-integration.so` and silently returns **all-zero (black) frames** — no exception raised.
- VirtualGL 3.1.2 is installed in the Docker image as optional fallback (`docker/Dockerfile:L108-L112`) but is not required for the standard path.
- Actual GPU CUDA acceleration for rendering is not used; rendering runs on CPU/software GLX. GPU is used only for ML model inference, not for CoppeliaSim rendering.

**Multi-camera support:** 5 cameras are defined and named in `rlbench/backend/scene.py:L45-L55`:
- `cam_over_shoulder_left` (left shoulder)
- `cam_over_shoulder_right` (right shoulder)
- `cam_overhead` (top-down overhead)
- `cam_wrist` (eye-in-hand)
- `cam_front` (front-facing)
Each has a paired `*_mask` sensor. Camera intrinsics/extrinsics are stored in `obs.misc` per step.

**Default resolution:** `(128, 128)` per camera. Set in `rlbench/observation_config.py:L13`: `image_size=(128, 128)`. The `README.md:L404` notes: "RLBench by default uses image observation sizes of 128×128." Configurable via `CameraConfig(image_size=(H,W))`.

**Vectorized / parallel envs:** Each RLBench environment instance launches one CoppeliaSim process (one window / one socket). True vectorized environments require spawning N separate CoppeliaSim processes. The Gymnasium async vector API is supported via `examples/rlbench_gym_vector.py:L32`: `gym.make_vec(..., vectorization_mode="async", vector_kwargs={"context": "spawn"})`. Dataset generation uses Python `multiprocessing` (`rlbench/dataset_generator.py:L4`, `L289`: `--processes` arg). There is no shared-memory vectorized path; each process is fully isolated.

---

## 4. observation_action_space

**Observation dict (`Observation` class, `rlbench/backend/observation.py:L4-L81`):**

| Field | Type | Description |
|---|---|---|
| `left_shoulder_rgb` | `np.ndarray (H,W,3) uint8` | Left over-shoulder camera RGB |
| `left_shoulder_depth` | `np.ndarray (H,W)` | Depth (normalized or meters) |
| `left_shoulder_mask` | `np.ndarray (H,W)` | Segmentation mask (object handles) |
| `left_shoulder_point_cloud` | `np.ndarray (H,W,3)` | 3D point cloud from depth |
| (same for `right_shoulder`, `overhead`, `wrist`, `front`) | | 5 cameras × 4 modalities |
| `joint_velocities` | `np.ndarray (7,)` | Arm joint velocities |
| `joint_positions` | `np.ndarray (7,)` | Arm joint positions |
| `joint_forces` | `np.ndarray (7,)` | Joint torques (signed by velocity direction) |
| `gripper_open` | `float` | 1.0 if open (>0.9), else 0.0 |
| `gripper_pose` | `np.ndarray (7,)` | EE pose [x,y,z,qx,qy,qz,qw] |
| `gripper_matrix` | `np.ndarray (4,4)` | EE transformation matrix |
| `gripper_joint_positions` | `np.ndarray (2,)` | Gripper finger joint positions |
| `gripper_touch_forces` | `np.ndarray` | Touch sensor forces at EE |
| `task_low_dim_state` | `np.ndarray` | Task-specific state (optional, use with caution) |
| `misc` | `dict` | Camera intrinsics/extrinsics, `variation_index`, `joint_position_action`, `joint_poses` |

**Action modes (`rlbench/action_modes/`):**

Arm action modes (`arm_action_modes.py`):
- `JointVelocity` — target joint velocities (7-DoF for Panda)
- `JointPosition(absolute_mode=True/False)` — absolute or delta joint positions
- `JointTorque` — joint torques
- `EndEffectorPoseViaPlanning(absolute_mode, frame, collision_checking)` — EE pose via RRTConnect motion planning, shape `(7,)` = [x,y,z,qx,qy,qz,qw]
- `EndEffectorPoseViaIK(absolute_mode, frame, collision_checking)` — EE pose via Jacobian IK, shape `(7,)`
- `ERJointViaIK` — EE pose + elbow joint(s) via IK, shape `(7+n_elbow_joints,)`

Gripper action modes (`gripper_action_modes.py`):
- `Discrete` — binary open/close (threshold 0.5), shape `(1,)`
- `GripperJointPosition(absolute_mode)` — finger joint position target, shape `(1,)`

Combined modes (`action_mode.py`):
- `MoveArmThenGripper` — sequential arm then gripper
- `JointPositionActionMode` — simultaneous delta joint + absolute gripper; bounds `[-0.1, 0.1]^7 + [0, 0.04]`

**Demo data format:**
- Stored as per-variation per-episode directories: `<root>/<task_name>/variation<N>/episodes/episode<M>/`
- Low-dim data: pickled list of `Observation` objects → `low_dim_obs.pkl` (`rlbench/backend/const.py:L22`)
- Images: PNG files per step in named subdirectories (`left_shoulder_rgb/`, `wrist_rgb/`, etc.)
- Variation descriptions: pickled list of NL strings → `variation_descriptions.pkl` (`rlbench/backend/const.py:L23`)
- Format is custom pickle + PNG, **not HDF5**.
- `Demo` class is a thin wrapper over `List[Observation]` with `random_seed` (`rlbench/demo.py:L7-L20`)

**Language annotation availability:** Yes. Each task's `init_episode(index)` returns a `List[str]` of NL descriptions for that variation. Example from `close_jar.py:L40-L43`: 4 descriptions including `'close the red jar'`, `'screw on the red jar lid'`, etc. `reach_target.py:L34-L37`: 3 descriptions including `'reach the red target'`. These descriptions are saved to `variation_descriptions.pkl` per variation at dataset generation time (`dataset_generator.py:L240-L242`). So: **language annotations are per variation, multiple phrasings per variation** (typically 3-5 per variation). This is natively built into every task — not a post-hoc annotation.

---

## 5. robot_models

**Default arm:** Franka Panda (7-DoF). `README.md:L350`: "For benchmarking, the arm should remain as the Franka Panda." Loaded from `rlbench/robot_ttms/panda.ttm` and the `Panda` class from PyRep.

**Supported arms and grippers** (`rlbench/const.py:L38-L43`):

| Key | Arm class | Gripper class | DoF |
|---|---|---|---|
| `'panda'` | `Panda` | `PandaGripper` | 7 |
| `'jaco'` | `Jaco` | `JacoGripper` | 6 |
| `'mico'` | `Mico` | `MicoGripper` | 6 |
| `'sawyer'` | `Sawyer` | `BaxterGripper` | 7 |
| `'ur5'` | `UR5` | `Robotiq85Gripper` | 6 |

Note: `README.md:L41-L55` also mentions arm names "franka", "mico", "jaco", "sawyer", "ur5".

**Suction gripper:** Not supported natively in the core `SUPPORTED_ROBOTS` dict. No `SuctionGripper` entry.

**Contact simulation:** CoppeliaSim physics handles contact. Grasping is simulated via `gripper.grasp(obj)` which creates a rigid attachment between the gripper and graspable objects (`rlbench/backend/scene.py:L429`). This is a "grasp hack" — not continuous contact force simulation. `README.md` "Gotchas" section does not mention gripper instability explicitly. The BridgeVLA ops note (`docker/bridgevla.md:L3`) states evaluation runs "on a single mid-range GPU (verified on RTX 3060 12 GB)" without mentioning contact instability. Known issues with gripper contact: the `CloseJar` task has `base_rotation_bounds` tuned specifically to prevent gripper rotation joint from reaching its limit during unscrewing (`rlbench/tasks/close_jar.py:L49-L55`): "Issue occured rarely so is only minor."

**Wrist camera:** All supported arms must have a wrist camera integrated into the TTM. `rlbench/const.py:L35-L36` comment: "Arms from PyRep need to be modified to include a wrist camera. Currently, only the arms/grippers below are supported."

---

## 6. ecosystem

**VLA / imitation learning papers benchmarking on RLBench (verified):**

| Paper | arXiv | Tasks on RLBench | Notes |
|---|---|---|---|
| PerAct (Shridhar et al., CoRL 2022) | 2209.05451 | **18 tasks, 249 variations** | Established the standard 18-task subset |
| RVT (Goyal et al., CoRL 2023) | 2306.14896 | **18 tasks, 249 variations** | Follows PerAct protocol; 26% higher success than PerAct |
| RVT-2 (Goyal et al., RSS 2024) | 2406.08545 | Same 18-task protocol | State-of-art 82% avg success (from 65%) |
| Act3D (Gervet et al., CoRL 2023) | 2306.17817 | **74 RLBench tasks** | Larger task subset |
| 3D Diffuser Actor (Ke et al., 2024) | 2402.10885 | RLBench + CALVIN | +18.1% abs over SOTA on RLBench multi-view |
| BridgeVLA (Li et al., NeurIPS 2025) | 2506.07961 | RLBench + COLOSSEUM | 88.2% avg success on RLBench, 64.0% on COLOSSEUM |

**Hiveformer:** Referenced in benchmarks but arXiv ID not confirmed from available searches.

**ARP (Autoregressive Policy):** Referenced in task description as benchmarking on RLBench but arXiv ID not confirmed.

**COLOSSEUM** (Pumacay et al., RSS 2024, arXiv:2402.08191): A **separate** benchmark with 20 manipulation tasks (not derived from RLBench tasks) that tests robustness to 14 perturbation axes (color, texture, size, lighting, distractors, physical properties, camera pose). Success degrades 30-50% per individual perturbation, ≥75% with multiple. BridgeVLA reports 64.0% on COLOSSEUM.

**Open-X-Embodiment / Hugging Face:** Not stated in RLBench paper or repo. RLBench is not in the Open-X-Embodiment dataset. No Hugging Face dataset card found.

**RLBench v2:** Not stated in the paper or repo. No version 2 found.

**PerAct-18 subset** is now the de facto standard evaluation protocol: 18 tasks, 25 demonstrations per variation, 100 evaluation episodes per task. The 18 tasks used in PerAct/RVT are listed in `docker/README.md:L191` as a directory name `peract18/` and described in `docker/examples/render_showcase.py` comments.

---

## 7. install_ops

**Install difficulty:** High. Requires:
1. CoppeliaSim 4.1.0 Edu (binary download, ~600 MB)
2. PyRep (Python bindings, from GitHub, requires CoppeliaSim installed first)
3. Python 3.8 **exactly** — `docker/Dockerfile:L9`: "PyRep needs exactly 3.8", `docker/Dockerfile:L71`: uses `deadsnakes/ppa` to get `python3.8`
4. Multiple X11/GL system libraries
5. An X display (real, Xvfb, or VirtualGL)

**CoppeliaSim version pinning:** Hard pinned to **4.1.0 Edu**. `docker/README.md:L63` explicitly warns: "newer = segfault". The Ubuntu 20.04 binary is used even on Ubuntu 22.04/24.04 hosts because CoppeliaSim bundles its own Qt5 (`docker/README.md:L62`).

**Python version pinning:** Exactly Python 3.8 (`docker/Dockerfile:L9,L81`).

**Qt/OpenGL dependency:** CoppeliaSim bundles Qt5 under `$COPPELIASIM_ROOT/{lib,platforms,xcbglintegrations}`. System Qt is not required. Critical env vars:
- `LD_LIBRARY_PATH=$COPPELIASIM_ROOT` — for CoppeliaSim's bundled `.so` files
- `QT_QPA_PLATFORM_PLUGIN_PATH=$COPPELIASIM_ROOT/platforms` — xcb platform plugin
- `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` — **THE critical fix** (`docker/Dockerfile:L172`): without this, xcb cannot find `xcbglintegrations/libqxcb-glx-integration.so` and silently produces all-zero camera frames

**X server requirement:** Mandatory. CoppeliaSim cannot run without an X display. Options:
1. **Xvfb** (standard headless): `Xvfb :99 -screen 0 1280x1024x24 +extension GLX +render -noreset` (`docker/entrypoint.sh:L14-L15`). Requires `QT_PLUGIN_PATH` fix to get real frames.
2. **nvidia-xconfig + `sudo X :99`** (bare-metal GPU): `README.md:L105-L119`. Requires root, modifies `/etc/X11/xorg.conf`.
3. **VirtualGL** (`vglrun -d egl0`): optional for GPU-accelerated GLX, installed in Docker image (`docker/Dockerfile:L108-L112`).

**Known Docker recipes:** This repo provides a fully working Dockerfile (`docker/Dockerfile`, 184 lines). BridgeVLA variant: `docker/bridgevla.Dockerfile`. Base: `nvidia/cuda:12.1.1-runtime-ubuntu22.04`. Final image size: ~6.6 GB (standard) or ~9 GB (BridgeVLA).

**Common breakage points** (documented in `docker/README.md:L85-L170`):
1. **All-zero camera frames** — symptom of missing `QT_PLUGIN_PATH`; no exception raised
2. **Segfault** — using CoppeliaSim newer than 4.1.0 with current PyRep
3. **TF/LLVM clash** — TensorFlow bundles its own LLVM and segfaults CoppeliaSim (`docker/bridgevla.md:L5`); workaround: `pip uninstall -y tensorflow`
4. **PaliGemma auth gate** — gated HuggingFace weights (`docker/bridgevla.md:L12-L14`)
5. **12 GB VRAM ceiling** for BridgeVLA — `select_feat_from_hm` allocates ~2 GiB int64 tensors; patched to chunk (`docker/bridgevla.md:L18-L20`)
6. **YARR single-episode flush** — `_SimpleAccumulator.pop()` needed `>1` episodes to emit summaries; patched to `>=1` (`docker/bridgevla.md:L26-L28`)

---

## 8. eval_protocol

**Task suite size:**
- Paper claims **100 tasks** (arXiv:1909.12271 abstract: "100 completely unique, hand-designed tasks")
- Repo contains **106 task Python files** (excluding `__init__.py`): `ls rlbench/tasks/ | grep -v __init__ | wc -l` → 106
- **Discrepancy:** Paper: 100 tasks, repo HEAD: 106 tasks (6 tasks added since paper). Both values are true at their respective times.
- **Task TTM files:** 108 entries in `rlbench/task_ttms/` (including `__init__.py` = 107 non-init; some tasks may share TTMs or have extras)

**Variation count per task:**
- Most tasks: **1 variation** (63 out of ~106 tasks have `return 1` in `variation_count()`)
- Color-based tasks: typically **20 variations** (one per color in `rlbench/const.py:L13-L33`; 20 colors defined)
- Some tasks: 2 or 3 variations
- Distribution from repo grep: 63 tasks × 1, 8 tasks × 3, 7 tasks × 2, remainder with higher counts
- PerAct/RVT protocol uses **249 variations across 18 tasks** (arXiv:2209.05451, arXiv:2306.14896)

**Success metric:** Binary task-completion check evaluated at every step. `rlbench/task_environment.py:L101`: `success, terminate = self._task.success()`. Success is defined per-task as meeting all `register_success_conditions()` — typically proximity sensors (object in target zone), detected conditions, or `NothingGrasped`. A sparse `reward = float(success)` (0.0 or 1.0) is returned (`task_environment.py:L103-L104`). Shaped rewards available for 2 tasks only (reach_target, take_lid_off_saucepan) via `shaped_rewards=True`.

**Train/eval split conventions:**
- Few-shot sets: `FS10_V1`, `FS25_V1`, `FS50_V1`, `FS95_V1` (10/25/50/95 train + 5 test tasks) — `rlbench/tasks/__init__.py:L114-L241`
- Multi-task sets: `MT15_V1`, `MT30_V1`, `MT55_V1`, `MT100_V1` (train only, no held-out test split) — `rlbench/tasks/__init__.py:L242-L256`
- PerAct protocol: no formal train/test task split; train on all 18 tasks, evaluate on same 18

**Generalization axes (what "variations" cover):**
- **Color** — target/distractor color selected from 20 named colors (`rlbench/const.py:L13-L33`: red, maroon, lime, green, blue, navy, yellow, cyan, magenta, silver, gray, orange, olive, purple, teal, azure, violet, rose, black, white)
- **Position** — objects randomly placed in workspace boundary via `SpawnBoundary.sample()` (`rlbench/backend/scene.py:L529-L537`)
- **Target identity** — which of N objects is the target (e.g., close the red jar vs. blue jar)
- **Pose** — task base randomly rotated within `base_rotation_bounds()` 
- Size/shape/texture variations: **not stated** as explicit variation axes in the repo; most variation is color + position

**Typical rollout count:** Not specified in the paper or core repo. PerAct/RVT protocol: 100 evaluation episodes per task × 18 tasks = 1800 total rollouts. Dataset generation default: `--episodes_per_task` argument (no hard default found in parser, user-specified).

**Episode length:** No hard limit enforced by the environment itself — `TaskEnvironment.step()` runs indefinitely until `terminate=True`. Example scripts use `episode_length = 40` steps (`examples/single_task_rl.py:L33`, `examples/rlbench_gym.py:L9`, etc.). BridgeVLA eval uses `--episode-length 25` (`docker/bridgevla.md:L77`). PerAct protocol uses 25 steps per episode (not stated in this repo — inferred from downstream paper).

---

## Cross-cutting notes for MuJoCo comparison

1. **CoppeliaSim vs. MuJoCo:** RLBench uses CoppeliaSim (proprietary Edu licence, non-commercial). All four MuJoCo-based benchmarks (LIBERO, Robosuite, Meta-World, ManiSkill) use MuJoCo (MIT licence since 2021, open-source). This is the most fundamental architectural difference.

2. **Scene authoring requires GUI:** New RLBench tasks require opening CoppeliaSim GUI to place waypoints in `.ttm` files. MuJoCo-based benchmarks define scenes programmatically in XML (MJCF) or Python.

3. **Demo format:** Pickled `List[Observation]` objects + per-frame PNGs (not HDF5). MuJoCo benchmarks typically use HDF5 (robosuite/LIBERO).

4. **Language annotations:** Native — every task variation returns NL descriptions from `init_episode()`. No post-hoc CLIP labeling needed.

5. **5-camera multi-modal obs:** RGB + depth + point cloud + segmentation mask from 5 viewpoints simultaneously. This is richer than most MuJoCo benchmarks by default.

6. **Headless complexity:** CoppeliaSim's X11 requirement and Qt plugin discovery bugs (`QT_PLUGIN_PATH` issue) make headless Docker deployment significantly more complex than MuJoCo (which is headless-native via EGL/OSMesa).
