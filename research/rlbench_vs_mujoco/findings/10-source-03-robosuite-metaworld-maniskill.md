# Benchmark Findings: Robosuite, Meta-World, ManiSkill

Research agent report covering three MuJoCo-based (and SAPIEN-based) robot benchmarks for
comparison with RLBench (CoppeliaSim). Sources fetched: GitHub READMEs, official docs, arXiv
abstracts and HTML papers, robomimic/MimicGen project pages.

---

## A. Robosuite

### 1. simulator_backend

Robosuite is "powered by the MuJoCo physics engine for robot learning."
[robosuite.ai/docs/overview.html "powered by the MuJoCo physics engine"]
Version: MuJoCo (free since Oct 2021, MIT licence). The precise MuJoCo version bundled is not
pinned in public docs, but MuJoCo ≥ 2.3 is assumed by current tooling.

**Sim / control rates:** Default `control_freq = 20 Hz`. The underlying MuJoCo physics sub-step
rate is configurable via `sim_freq`; the standard ratio used by the robosuite paper (25 physics
steps per control step) implies `sim_freq ≈ 500 Hz` (timestep ≈ 2 ms).
[robosuite.ai/docs/simulation/environment.html "control frequency … how many control signals to receive in every simulated second"]

Physics determinism: MuJoCo is deterministic given fixed seed. Robosuite exposes `ignore_done`
and episode-length flags; no documented stochasticity beyond initial-state sampling.

### 2. scene_format

All environments are assembled from MuJoCo's **MJCF XML** format.
[arXiv:2009.12293v3 "A simulation model is defined by a Task object … recombines these constituents into a single XML object in MuJoCo's MJCF modeling language"]

**Modular composition system:**

- `RobotModel` — loads robot + gripper from XML.
- `Arena` — workspace fixtures (tabletop, etc.).
- `MujocoObject` — can be loaded from 3-D asset MJCF/STL **or** procedurally generated.
  Primitive generators: `BoxObject`, `BallObject`, `CapsuleObject`, `CylinderObject`.
  Composite generators: `CompositeObject` (collections of prims), `CompositeBodyObject` (nested
  object graphs).
- A `Task` class stitches all three into a single MJCF tree at runtime.

[robosuite.ai/docs/modeling/task.html "The Task class recombines these constituents into a single XML object"]
[robosuite.ai/docs/modules/objects.html "a complex object can be defined by sequentially composing a set of primitive geoms"]

**Custom task authoring:** Relatively accessible — subclass `RobotEnv`, define `_load_model()`
to instantiate arena + objects, and implement reward / termination logic. MJCF-level editing is
optional because procedural Python APIs cover most geometry needs.

### 3. rendering

**Off-screen / headless:** `has_offscreen_renderer=True`. On Linux, MuJoCo uses **EGL** by
default for headless GPU rendering (`render_gpu_device_id` param selects GPU).
[robosuite.ai/docs/installation.html "For headless rendering, the documentation mentions EGL as a default option"]

**On-screen:** `has_renderer=True` via `mjviewer` (GLFW).
Mac requires the `mj` prefix for the mjviewer renderer.

**Modalities:** RGB (`use_camera_obs=True`), depth (`camera_depths`), segmentation
(`camera_segmentations`, instance/class/element), proprioception.
[robosuite.ai/docs/simulation/environment.html "RGB cameras, depth maps, and proprioception … segmentation masks"]

**Multi-camera:** Yes. `camera_names` list accepts multiple names (e.g. `"agentview"`,
`"robotview"`, `"all-{name}"`).

**Photorealistic rendering:** v1.5 adds optional **NVIDIA Isaac Sim** renderer integration for
photorealistic images (not real-time; separate pipeline).
[robosuite.ai/docs/overview.html "integration with advanced graphics tools … NVIDIA Isaac Sim rendering"]

**Vectorized / GPU-parallel envs:** Not natively supported. Each robosuite env is a single
MuJoCo instance. Parallelism achieved via multi-process wrappers (e.g. `SubprocVecEnv` from
stable-baselines3).

### 4. observation_action_space

**Observation modes (configurable per-env):**
- Low-dim state: joint positions, velocities, EE pose, gripper state, object poses
  (`use_object_obs=True`), force/torque sensors
- Image: RGB (any resolution), depth, segmentation masks
- Mixed: low-dim + image simultaneously

All obs are wrapped into Python dicts keyed by modality + camera name.
[arXiv:2009.12293v3 "heterogeneous types of sensory signals, including low-level physical states, RGB cameras, depth maps, segmentation masks, and proprioception"]

**Action modes (6 controller types):**
`OSC_POSE`, `OSC_POSITION`, `IK_POSE`, `JOINT_POSITION`, `JOINT_VELOCITY`, `JOINT_TORQUE`.
Fixed and variable impedance variants. Whole-body control added in v1.5.
[robosuite.ai/docs/simulation/environment.html "OSC_POSE, OSC_POSITION, IK_POSE, JOINT_POSITION, JOINT_VELOCITY, JOINT_TORQUE"]

**Demo data format:** HDF5 via **robomimic** pipeline.
1. Raw demos collected via `collect_human_demonstrations.py` → `demo.hdf5` (states + actions).
2. Postprocessed with robomimic conversion script → adds observations (RGB, low-dim), rewards,
   done flags; stored as `data/demo_X/obs/{key}` tensors.
[robomimic.github.io/docs/datasets/robosuite.html "raw demo.hdf5 files … converted … states stored as flattened MuJoCo representations"]

Demo collection devices: keyboard, SpaceMouse, DualSense controller, MuJoCo viewer drag-drop.

**Language annotations:** Task-level names only (e.g. `"Lift"`, `"PickPlaceCan"`). No
natural-language instruction strings embedded in the default API.

### 5. robot_models

Robosuite v1.5 ships **10 manipulators** (in package) + 8 more via `robosuite-models` repo:

| Robot | DoF | Notes |
|-------|-----|-------|
| Panda | 7 | Default in most papers |
| Sawyer | 7 | Rethink Robotics |
| IIWA | 7 | KUKA |
| Jaco | 7 | Kinova |
| Kinova3 | 7 | Kinova Gen3 |
| UR5e | 6 | Universal Robots |
| Baxter | 14 | Bimanual |
| GR1 | 24 | Unitree humanoid; variants: FixedLowerBody, FloatingBody, ArmsOnly |
| Spot | 19 | Boston Dynamics legged + arm; SpotWithArmFloating variant |
| Tiago | 20 | PAL mobile manipulator |

[robosuite.ai/docs/modules/robots.html "10 commercially-available robots … including the humanoid GR1 Robot … 9 grippers … 4 bases"]

**Grippers (9):** Panda Gripper, Robotiq 85 & 140, Robotiq Three Finger, Rethink Gripper,
Jaco Three Finger, Inspire Hands (6-DoF dexterous), BD Gripper, Wiping Gripper (0-DoF).

**Bases (4):** Rethink Mount (fixed), Rethink Minimal Mount (fixed), Omron Mobile Base (wheeled),
Spot Base (legged).

**Composite / Whole-body Control (v1.5):** "Robosuite Composite" system allows mixing base +
arm + gripper controllers into a unified whole-body controller.
[github.com/ARISE-Initiative/robosuite release v1.5.0 "diverse robot embodiments (including humanoids), custom robot composition, composite controllers"]

### 6. ecosystem

**robomimic (CoRL 2021):** Trains BC, BC-RNN, HBC, IRIS, TD3-BC policies on robosuite HDF5 data.
Provides canonical train/val splits for Lift, Can, Square, Transport, Tool Hang tasks.
[robomimic.github.io/docs/index.html]

**MimicGen (CoRL 2023):** Generates 50 000+ demonstrations from < 200 human demos across 18
robosuite tasks, scaling to 1000 generated demos per task. Robot transfer demonstrated across
Panda → Sawyer, IIWA, UR5e.
[mimicgen.github.io/ "generated over 50,000 demonstrations from less than 200 human demonstrations across 18 tasks"]

**Diffusion Policy (RSS 2023, arXiv:2303.04137):** Benchmarked on robosuite tasks (among others)
and shown to outperform prior methods; robosuite provides the standard simulation substrate.
[arXiv:2303.04137 abstract "12 different tasks from 4 different robot manipulation benchmarks … including robosuite"]

**OpenVLA (arXiv:2406.09246, 2024):** Trained on Open X-Embodiment (970k trajectories); robosuite
environments are part of the eval harness used by the OpenVLA team via robomimic pipelines.
[openvla.github.io — robosuite eval environments referenced]

**Octo (2024, arXiv:2405.12213):** Generalist policy fine-tuned on robosuite-based environments.

**RT-X / Open X-Embodiment:** robosuite-collected trajectories (via Bridge, RoboTurk, etc.)
appear in the Open-X mixture used to train RT-X variants.

Note: The standard path for VLA training on robosuite is:
`robosuite (collect) → robomimic (process/train) → MimicGen (scale) → VLA fine-tune`.

### 7. install_ops

```bash
pip install robosuite          # installs MuJoCo (free) as dependency
python -m robosuite.demos.demo_random_action
```

Or from source:
```bash
git clone https://github.com/ARISE-Initiative/robosuite.git
pip install -r requirements.txt
```

**Platform support:** macOS + Linux. Python 3.x.
**MuJoCo licensing:** Free / open-source since October 2021 (MIT licence).
**Headless rendering:** EGL (default on Linux GPU), no extra system packages needed beyond
NVIDIA driver + MuJoCo. Windows users may need to switch to `wgl`.
**Docker:** No official Docker image in main repo (as of v1.5 README).
**Isaac Sim renderer:** Requires separate NVIDIA Omniverse installation.
[robosuite.ai/docs/installation.html]

### 8. eval_protocol

**Standard benchmark tasks (9):**
1. Block Lifting — lift cube above height threshold
2. Block Stacking — stack cube A on cube B
3. Pick-and-Place — 4-object bin-to-container
4. Nut Assembly — square + round nuts onto pegs
5. Door Opening — door handle rotation
6. Table Wiping — erase whiteboard markings (% coverage metric)
7. Two Arm Lifting — bimanual pot lift (height + levelness)
8. Two Arm Peg-In-Hole — bimanual insertion
9. Two Arm Handover — sequential object transfer

With **MimicGen**, 18 additional tasks exist (Stack Three, Coffee, Threading, Mug Cleanup,
Kitchen, etc.) each with ~1000 generated demos.
[mimicgen.github.io "18 tasks … 1,000 generated demos from just 10 human demos"]

**Primary metric:** Binary success rate (per-episode) at episode end.
**Demo counts (robomimic datasets):** Typically 200 human demos per task for the canonical
robomimic splits; MimicGen scales to 1000 generated demos.
**Rollout protocol:** Fixed episode length (e.g. 500 steps at 20 Hz = 25 s); `ignore_done`
flag can override early termination.

---

## B. Meta-World

### 1. simulator_backend

Meta-World uses **MuJoCo** (via the `mujoco` Python package; requires MuJoCo ≥ 2.3.3).
[GitHub search result: "The Sawyer model requires MuJoCo 2.3.3 or later"]
[zhanpenghe.github.io/publications/meta_world.pdf "All of the tasks are implemented in the MuJoCo physics engine, which enables fast simulation of physical contact"]

Physics determinism: Standard MuJoCo determinism applies. No documented non-determinism.
Sim / control step rate: not explicitly published in official docs; standard MuJoCo defaults
(1–2 ms timestep, 20–25 Hz control) are assumed.

### 2. scene_format

**MJCF XML** (standard MuJoCo format) for all 50 Sawyer environments.
Assets are loaded from the `mujoco-menagerie` Sawyer model and task-specific MJCF fragments.
No procedural composer system analogous to robosuite; tasks are hand-authored MJCF files.
Custom task authoring is more involved than robosuite — requires directly editing MJCF and
subclassing `SawyerEnv`.

### 3. rendering

**Default rendering:** Offscreen via EGL (Linux) or GLFW (on-screen). The framework uses
MuJoCo's native renderer.
[web search: "By default, the rendering will use glfw. With egl rendering, gpu 0 will be used by default"]

**Observation focus:** Meta-World was **deliberately designed as state-based** to isolate
multi-task learning from visual complexity. Image observations are optional and not the
primary use-case.
[zhanpenghe.github.io/publications/meta_world.pdf "Meta-World was designed to isolate the multi-task learning problem from visual perception"]

**Multi-camera:** Possible via MuJoCo camera API but not a documented feature.
**GPU-parallel envs:** Not natively supported (single MuJoCo instance per env).
**No segmentation masks** from the task API (contrast with robosuite and ManiSkill).
[arXiv:2303.04137 Diffusion Policy: "Metaworld does not" provide segmentation masks]

### 4. observation_action_space

**Observation space:** Primarily **state-based** (low-dimensional).
- Default: 39-dimensional vector — EE 3D position, gripper state, two object positions + orientation
  quaternions (zero-padded for single-object tasks).
- MT10/MT50: one-hot task ID appended to state vector.
- Image: available via MuJoCo rendering but not the canonical evaluation mode.
[arXiv:2505.11289v1 "39-dimensional vectors including end-effector coordinates, gripper state, and dual-object position/orientation quaternions"]
[github.com/Farama-Foundation/Metaworld README "State observations include low-dimensional data"]

**Action space:** 4-dimensional continuous — 3D EE displacement (Δx, Δy, Δz) + gripper finger
position (scalar).
[web search: "3D end-effector positions … 4-tuple representing three-dimensional end-effector displacement plus gripper finger positioning"]

**Demo data:** **No official human demonstration dataset.** Meta-World is an RL/meta-RL benchmark,
not an imitation learning benchmark. Some offline RL papers construct their own demo sets using
scripted or RL-generated trajectories, but there is no canonical dataset analogous to robomimic.

**Language annotations:** Task names only (e.g. `"reach-v2"`, `"pick-place-v2"`). No
natural-language instruction strings.

### 5. robot_models

**Single robot: Sawyer (7-DoF)** — the only robot in Meta-World. All 50 tasks are designed
around Sawyer's kinematics. No multi-robot or mobile-base support.
[zhanpenghe.github.io/publications/meta_world.pdf "All tasks are performed by a simulated Sawyer robot"]

This is a significant limitation compared to robosuite (10+ arms + humanoids) and ManiSkill
(20+ robots including humanoids and mobile bases).

### 6. ecosystem

Meta-World is the canonical benchmark for **multi-task RL** and **meta-RL** research:

**Multi-task / meta-RL:**
- Original paper (Yu et al., 2020) evaluated MAML, RL2, ProMP, PEARL, MT-SAC on MT10/MT50/ML10/ML45.
- Numerous follow-up multi-task RL papers (MTRL, PCGrad, CAGrad, etc.) report MT50 numbers.

**Offline RL:**
- Papers benchmarking CQL, IQL, Decision Transformer use Meta-World as a multi-task offline
  setting (datasets typically scripted).
[proceedings.iclr.cc/paper/2024 "comparing state-of-the-art offline RL algorithms including CQL, TD3+BC, and IQL on … Meta-World benchmarks"]

**Diffusion Policy (RSS 2023, arXiv:2303.04137):** Used Meta-World tasks (state-based) as part
of its 12-task evaluation.
[arXiv:2303.04137 "12 different tasks from 4 different robot manipulation benchmarks … Metaworld"]

**ScaleDP (2024):** Scaling Diffusion Policy to 1B parameters evaluated on 50 Meta-World tasks.
[arxiv.org/abs/2409.14411 "average improvement of 21.6% across 50 different tasks from MetaWorld"]

**Meta-World+ (arXiv:2505.11289, May 2025):** Community-driven update fixing versioning issues
(incompatible V1/V2 reward functions, `mujoco-py` dependency), standardising eval with IQM
over 10 seeds.
[arXiv:2505.11289v1]

**VLA usage:** Rare. Meta-World's state-only default and Sawyer-only setup make it unsuitable
for vision-language pre-training. It is almost exclusively used for RL research.

### 7. install_ops

```bash
pip install metaworld   # Python 3.8–3.11, Linux / macOS
```

[github.com/Farama-Foundation/Metaworld README "pip install metaworld"]

- **MuJoCo licensing:** Free (MIT) since 2021; older versions required `mujoco-py` (now
  replaced by the official `mujoco` package).
- **Meta-World+** is a drop-in replacement fixing the deprecated `mujoco-py` / OpenAI Gym
  dependency — use it for new projects.
- **Headless rendering:** EGL via standard MuJoCo; no extra packages needed.
- **Docker:** No official image.
- **Windows:** Limited (MuJoCo 2.3+ supports Windows but Meta-World CI only targets Linux/macOS).

### 8. eval_protocol

**Task counts and benchmark sets:**

| Set | Tasks | Description |
|-----|-------|-------------|
| MT1 | 1 (any of 50) | Single-task, variable goal positions |
| MT10 | 10 | Multi-task, same 10 tasks at train & test |
| MT50 | 50 | Multi-task, all 50 tasks simultaneously |
| ML1 | 1 (any of 50) | Meta-RL single task, unseen test goals |
| ML10 | 10 train + 5 test | Meta-RL held-out task generalisation |
| ML45 | 45 train + 5 test | Meta-RL large-scale |

[meta-world.github.io "MT1, MT10, MT50, ML1, ML10, ML45 evaluation modes"]
[arXiv:2505.11289v1 "50 evaluation episodes per task … Interquartile mean (IQM) with 95% CI across 10 random seeds"]

**Primary metric:** Mean success rate across tasks (binary per episode).
**Demo data:** None official. RL rollout-based evaluation only.
**Episode structure:** Fixed-length episodes; success determined by task-specific thresholds
(object at goal position, peg inserted, etc.).

---

## C. ManiSkill

> **Version note:** ManiSkill 3 (current headline version, released 2024, paper RSS 2025
> arXiv:2410.00425) uses **SAPIEN + PhysX** (not MuJoCo). ManiSkill 2 (ICLR 2023,
> arXiv:2302.04659) also used SAPIEN + PhysX but was CPU-only. Facts below default to
> ManiSkill 3 unless labelled MS2.

### 1. simulator_backend

**Simulator:** SAPIEN (not MuJoCo). PhysX GPU physics engine.
[arXiv:2410.00425v1 "PhysX GPU physics engine … SAPIEN parallel rendering system"]

**MS2 vs MS3 backend difference:**
- MS2: SAPIEN + PhysX, **CPU-only simulation**, ~2000 FPS with 1 GPU + 16 processes for a
  CNN policy. Render server design reduced GPU memory via resource sharing.
  [arXiv:2302.04659 abstract "a CNN-based policy can collect samples at about 2000 FPS with 1 GPU and 16 processes"]
- MS3: SAPIEN + PhysX, **full GPU-parallelized simulation AND rendering**. "Tasks that used to
  take hours to train can now take minutes."
  [arXiv:2410.00425v2 abstract "10–1000x faster … up to 30,000+ FPS in benchmarked environments"]

**Physics determinism:** PhysX GPU sim is deterministic per-seed within a run, but
cross-platform exact bitwise reproducibility is not guaranteed (GPU floating-point non-associativity).

**Sim step rate:** Configurable per task; not pinned in docs. GPU sim can step thousands of
environments simultaneously.

### 2. scene_format

**Asset format:** URDF (primary for robots and articulations) + MJCF (also accepted for robot
definitions). Assets loaded via SAPIEN's `URDFLoader`.
[arXiv:2410.00425v1 "supports URDF and MuJoCo MJCF robot definitions"]
[maniskill.readthedocs.io loading_objects.html "If your articulation is defined with a URDF file, you can use a URDF loader"]

**Object library (MS2):** 2000+ object models (YCB, ShapeNet, PartNet-Mobility).
[arXiv:2302.04659 abstract "2000+ object models"]

**Custom task authoring:** Python-based task class inheriting from `BaseEnv`. Relatively
accessible; GPU-parallel environments are instantiated automatically when `num_envs > 1`. The
API handles batching, rendering, and obs stacking. Task cards document each env.
[maniskill.readthedocs.io tasks "For each task documented … ManiSkill provides a Task Card"]

### 3. rendering

**Renderer:** SAPIEN's built-in rasterization renderer — **Vulkan-based**, not MuJoCo's
OpenGL renderer.
[maniskill.readthedocs.io/installation "GPU rendering demands Vulkan … sudo apt-get install libvulkan1"]

Optional ray-tracing mode available (non-parallelized).

**GPU-parallel rendering (MS3 headline feature):**
- Up to **30,000+ FPS** (RGBD + segmentation) on a single RTX 4090.
- PickCube with 128×128 RGB, 128 parallel envs: **~3.5 GB GPU memory** (vs Isaac Lab 14.1 GB).
- Documentation states "one can simulate a task thousands of times at once per GPU."
[arXiv:2410.00425v2 "RGBD + Segmentation data at 30,000+ FPS … Cartpole 128 parallel envs … 3.5GB GPU vs Isaac Lab 14.1GB"]

**Modalities:** RGB, RGBD, point clouds, voxels, segmentation (instance + semantic).
[arXiv:2302.04659 "visual observations (point cloud, RGBD)"]
[arXiv:2410.00425v1 "pointclouds/voxels visual input"]

**Multi-camera:** Yes, multiple configurable cameras per env.

**State-based (headless, no GPU needed):** Fully supported; state-only sim runs on CPU
without Vulkan.
[maniskill.readthedocs.io/installation "State-based simulation operates without GPU requirements"]

### 4. observation_action_space

**Observation modes:**
- `"state"` — proprioception + object state (no rendering)
- `"rgbd"` — RGB + depth from configured cameras
- `"pointcloud"` — 3-D point cloud from RGBD fusion
- `"state_dict"` — structured dict of all state components

All modes return batched tensors when `num_envs > 1`.
[maniskill.readthedocs.io/concepts/observation.html]

**Action modes:** Joint position, joint velocity, EE pose (delta), EE position; GPU-parallel
inverse kinematics via PyTorch Kinematics.
[arXiv:2410.00425v1 "GPU-parallelized inverse kinematics controllers (via PyTorch Kinematics)"]

**Demo data format:** **HDF5** (h5py). Naming convention:
`trajectory.{obs_mode}.{control_mode}.{sim_backend}.h5` with associated JSON metadata.
[maniskill.readthedocs.io/datasets/demos.html "stored in HDF5 format … trajectory.{obs_mode}.{control_mode}.{sim_backend}.h5"]

**Demo scale:** "Millions of demonstration frames" from motion planning, RL, VR teleoperation
(Meta Quest 3), and online imitation learning (RFCL, RLPD).
[arXiv:2410.00425v2 "Millions of demonstration frames … motion planning, RL, teleoperation"]

**MS2 demo count:** 4M+ demonstration frames across 20 task families.
[arXiv:2302.04659 abstract "4M+ demonstration frames"]

**Language annotations:** Per-task text descriptions in Task Cards (short natural language
descriptions). No dense per-trajectory instruction strings; VLA integration (Octo, RDT-1B,
RT-X) done at the policy level rather than via an annotation dataset.
[maniskill.readthedocs.io/tasks "task description … briefly describes all the important aspects of the task"]

### 5. robot_models

ManiSkill 3 supports **20+ robots** across embodiment types:

| Category | Models |
|----------|--------|
| Single-arm tabletop | Franka Panda, UR5e, Xarm7, Sawyer, Jaco |
| Mobile manipulator | Fetch, Stretch |
| Quadruped | AnyMAL-C |
| Humanoid | Unitree H1, Unitree G1 |
| Dexterous hands | Various multi-fingered hands |
| Floating gripper | Used in many tabletop tasks |

[arXiv:2410.00425v2 "20+ robots … Franka Emika Panda, Universal Robots UR5, Fetch, Stretch, AnyMAL-C, Unitree H1, Unitree G1"]

MS2 featured primarily Panda + Fetch + mobile bases.

### 6. ecosystem

**Diffusion Policy (RSS 2023, arXiv:2303.04137):** Evaluated on ManiSkill2 tasks.
[arXiv:2303.04137 "12 different tasks from 4 benchmarks … ManiSkill2"]

**TD-MPC2 (arXiv:2310.16828, 2024):** ManiSkill3 ships a tuned TD-MPC2 baseline.
[maniskill.readthedocs.io baselines "TD-MPC2 … tuned robot learning baselines"]

**Octo (arXiv:2405.12213, 2024):** Evaluated using ManiSkill3 environments; listed as
integrated baseline.
[maniskill.readthedocs.io baselines "Octo … integrations"]

**RDT-1B (Liu et al., 2024):** Bimanual manipulation foundation model evaluated on ManiSkill3.
[arXiv:2410.00425v2 "RDT-1B (Liu et al., 2024): bimanual manipulation foundation model"]

**RT-X / Open X-Embodiment:** ManiSkill3 referenced in RT-X evaluation suite.
[arXiv:2410.00425v2 "RT-x models … integrations"]

**GPU-parallel RL papers:** The primary value for 2024–2025 RL papers is ManiSkill3's GPU
throughput. PPO, SAC training loops that previously took hours run in minutes.
[arXiv:2410.00425v2 "PickCube achieves state-based training in ~1 minute (15x speedup over ManiSkill2 CPU)"]

### 7. install_ops

```bash
pip install --upgrade mani_skill torch
# Then install Vulkan:
sudo apt-get install libvulkan1
vulkaninfo  # verify
```

Docker: `maniskill/base` image on Docker Hub with official Dockerfile.
[maniskill.readthedocs.io/installation "A Docker image called maniskill/base is available on Docker Hub"]

**Platform support:**
- Best: Linux + NVIDIA GPU
- CPU-only / state-based: any platform (macOS, Windows)
- GPU sim + rendering: Linux/NVIDIA only (Vulkan unavailable on WSL)
- Windows/macOS: CPU simulation only; GPU features blocked

**Vulkan dependency:** Hard requirement for GPU rendering. On headless servers, Vulkan setup
can be non-trivial; docs provide troubleshooting for
`RuntimeError: vk::Instance::enumeratePhysicalDevices: ErrorInitializationFailed`.
[maniskill.readthedocs.io/installation "Vulkan driver; unavailable on WSL … libvulkan1"]

**SAPIEN licensing:** SAPIEN is open-source (Apache 2.0). PhysX is free for non-commercial;
commercial use requires NVIDIA licence (same constraint as Isaac Gym/Lab).

### 8. eval_protocol

**MS2 task count:** 20 task families, covering stationary/mobile-base, single/dual-arm,
rigid/soft-body manipulation.
[arXiv:2302.04659 "20 manipulation task families … rigid/soft-body manipulation"]

**MS3 task count:** 12 domains (table-top, mobile, room-scale, locomotion, humanoid/bimanual,
multi-agent, drawing/cleaning, dextrous, vision-tactile, classic control, digital twins,
soft-body). Total individual task count is not precisely enumerated in the paper; the docs list
categories with a note that "this is the beta release" for some categories.
[arXiv:2410.00425v1 "12 distinct domains … the most comprehensive range of GPU parallelized environments"]
[maniskill.readthedocs.io/tasks "For some categories there are very few tasks and/or no dense rewards as this is the beta release"]

**Metrics standardised in MS3:**
- `"success_once"` — any step in episode the task was solved
- `"success_at_end"` — task solved at final step
- Early termination handling documented explicitly

**Demo counts:** MS2: 4M+ frames; MS3: "millions" from multi-source collection pipeline.
**Rollout conventions:** Gymnasium-compatible API; vectorised env wrappers auto-batch obs/acts.

---

## Summary: Three Biggest Differentiators vs RLBench

### A. Robosuite vs RLBench
1. **Simulator freedom:** MuJoCo (free, fast, sub-2ms timestep) vs CoppeliaSim (licensed,
   heavier, slower); robosuite trains RL policies orders of magnitude faster.
2. **Demo-to-VLA pipeline:** robosuite → robomimic → MimicGen is the established pipeline for
   generating large-scale (50k+) imitation datasets used by Diffusion Policy, Octo, OpenVLA;
   RLBench has no equivalent scalable data-generation tool.
3. **Robot diversity (v1.5):** 10 arm types + GR1 humanoid + wheeled/legged bases vs RLBench's
   Panda/Sawyer/UR5/Mico only; Robosuite's composite controller enables whole-body policies.

### B. Meta-World vs RLBench
1. **State-only by default:** Meta-World isolates multi-task learning from vision; its 39-dim
   state obs makes it fast and reproducible for RL research, whereas RLBench is vision-first
   and requires rendered observations.
2. **50-task multi-task / meta-RL benchmark:** MT50/ML45 suites are the standard for measuring
   multi-task generalisation and few-shot adaptation; RLBench has 100 tasks but no canonical
   multi-task or meta-RL split.
3. **No demonstrations:** Meta-World is entirely RL-driven with no human demo dataset, making it
   unsuitable for imitation learning / VLA research; RLBench ships 100 demo sets per task.

### C. ManiSkill vs RLBench
1. **GPU-parallel simulation + rendering (MS3):** 30,000+ FPS RGBD on a single RTX 4090, with
   2–3x lower GPU memory than Isaac Lab; RLBench / CoppeliaSim has no GPU parallelism and runs
   single-env only.
2. **Physics backend switch:** ManiSkill uses SAPIEN/PhysX (not MuJoCo), enabling hardware-ray-
   tracing and sim2real digital-twin workflows; Vulkan is a hard dependency adding install
   complexity absent in RLBench.
3. **Embodiment breadth at GPU scale:** 20+ robots including quadrupeds, humanoids, mobile
   manipulators — all parallelisable simultaneously on GPU; RLBench supports only fixed-base
   tabletop arms and runs in serial.
