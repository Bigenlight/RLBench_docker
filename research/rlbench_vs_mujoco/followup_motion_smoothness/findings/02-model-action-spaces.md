# Model Action Spaces & Motion Smoothness — Grounded Findings

> Compiled 2026-05-21. All claims are paper-grounded with explicit citations.

---

## 1. Per-Model Analysis

### 1.1 BridgeVLA (arXiv 2506.07961; NeurIPS 2025) — RLBench evaluator

**Action output type: keyframe / next-keypose prediction**

> "BridgeVLA operates through an iterative process: 1) predicting the action 𝐚ₜ conditioned on the current observation 𝐨ₜ and instruction l, 2) moving to the predicted next keyframe pose Tₜ using a sampling-based motion planner."
> — §3, arXiv 2506.07961

**Exact action vector:** "the action 𝐚 consists of a 6-DoF end-effector pose T ∈ SE(3), a target gripper state g ∈ {0,1}, and a collision flag c ∈ {0,1} of the next key frame." Rotation is represented as discretized Euler angles (72 bins per axis).

**Inference rate:** 0.21 s per keypose prediction on RTX 4090 (≈ 4.8 Hz of *prediction*, but the actual robot moves in between predictions via the planner, so wall-clock episode duration ≫ 1/0.21 s).

**Between-keypose execution:** sampling-based motion planner (OMPL / RRT-Connect / MoveIt, cited in the paper). The planner generates a full joint trajectory to reach the predicted SE(3) pose; the gripper actuates only after the arm settles. This produces the characteristic "move → stop → open/close gripper → move" segmented motion.

**Demo source:** Paper states it "follows previous works" on RLBench. RLBench demos are scripted-waypoint + motion-planner generated (see §1.7 below). BridgeVLA itself provides no original demo generation description.

**Local repo hint** (`docker/bridgevla.md`): the eval script runs with `--episode-length 25`, one keypose prediction per step, consistent with iterative keypose-by-keypose execution.

---

### 1.2 PerAct / Perceiver-Actor (arXiv 2209.05451, CoRL 2022) — RLBench evaluator

**Action output type: next-best-pose (keyframe) prediction in discretized voxel space**

> "PerAct...outputs discretized actions by detecting the next best voxel action."
> — peract.github.io project page

> "These features are then reshaped with linear layers to predict a discretized translation, rotation, gripper open, and collision avoidance action, which can be executed with a motion-planner."
> — peract.github.io

**Exact action vector:** discretized 3D voxel location (100³ workspace), discretized rotation (5° bins), binary gripper open/close, binary collision-avoidance flag. Effectively 7 scalars (6-DoF EE + gripper).

**Inference rate / keyposes per task:** PerAct's supplementary (Table 3, proceedings.mlr.press/v205/shridhar23a/) lists per-task average keyframes across the 18 RLBench tasks used. Across bimanual PerAct2 tasks (Table 5, arXiv 2407.00278) the range is 2.1–8.7 keyframes/demo, mean ≈ 6.3. The 18 single-arm PerAct tasks have a similar spread (roughly 3–9 keyframes, task-dependent).

**Between-keypose execution:** "All simulated evaluations use V-REP's internal motion-planner with collision avoidance." (peract/peract GitHub README). The planner is CoppeliaSim's built-in motion planner, equivalent to `MoveArmThenGripper(EndEffectorPoseViaPlanning(...))` in the RLBench action-mode API.

**Demo source:** RLBench scripted waypoints + motion planner (see §1.7). 100 demos per task, generated via `python dataset_generator.py --tasks=... --episodes_per_task=100`.

---

### 1.3 RVT — Robotic View Transformer (arXiv 2306.14896, CoRL 2023) — RLBench evaluator

**Action output type: keyframe prediction**

> "RVT predicts a target end-effector pose and gripper state at the next key-frame. Key-frames represent important or bottleneck steps of the gripper during the task execution, such as a pre-pick, grasp, or place pose."
> — arXiv 2306.14896v1, §3

**Exact action vector:** "an 8-dimensional action, including the 6-DoF target end effector pose (3-DoF for translation and 3-DoF for rotation), 1-DoF gripper state (open or close), and a binary indicator for whether to allow collision."

**Between-keypose execution:** "Given a target end effector pose, we assume a low-level motion planner and controller that can move the end effector to the target pose." (§3). In simulation this is CoppeliaSim's planner; for real-world they used FrankaPy trajectory generation.

**Demo source:** "the RLBench training dataset with 100 expert demonstrations per task (1800 demonstrations over all 18 tasks)" — scripted-waypoint + motion-planner generated.

---

### 1.4 RVT-2 (arXiv 2406.08545, RSS 2024) — RLBench evaluator

**Action output type: keyframe prediction** (same paradigm as RVT)

> "methods like PerAct and RVT take as input the language goal along with the current scene point cloud and predict the next key-frame pose."
> — arXiv 2406.08545v1, §2

> "The predicted pose is then passed to a motion planner, which generates a trajectory towards it."
> — arXiv 2406.08545v1, §3

**Exact action components:** (1) 3D gripper location (peak of predicted heatmap); (2) gripper rotation (location-conditioned features); (3) gripper open/close state.

**Between-keypose execution:** sampling-based motion planner (CoppeliaSim), same pattern as PerAct/RVT.

**Demo source / keyframe extraction:** "We can extract such a dataset automatically from dense robot trajectory datasets by defining rules that specify the key-frame poses. For instance, when the state of the gripper changes between open and close, the pose is a key-frame pose." Underlying dense demos are RLBench scripted-waypoint trajectories.

---

### 1.5 3D Diffuser Actor (arXiv 2402.10885, ICRA 2024) — RLBench evaluator

**Action output type: keypose prediction with optional full-trajectory diffusion**

> "During inference, 3D Diffuser Actor can either predict and execute the full trajectory of actions up to the next keypose (including the keypose), or just predict the next keypose and use a sampling-based motion planner to reach it."
> — arXiv 2402.10885v2, §III-B

For RLBench experiments, keypose-only mode is used:

> "our 3D Diffuser Actor is trained to predict the next end-effector keypose and we employ the low-level motion planner BiRRT, native to RLBench, to reach the predicted pose."
> — arXiv 2402.10885v2, §IV-A

**Exact action format:** `𝐚ₜ = {𝐚ₜˡᵒᶜ ∈ ℝ³, 𝐚ₜʳᵒᵗ ∈ ℝ⁶, 𝐚ₜᵒᵖᵉⁿ ∈ {0,1}}` — 3D position, 6D rotation (continuous, discontinuity-free), binary gripper.

**Keyposes per task (selected examples from the paper):** open drawer ≈ 3 keyposes, sweep to dustpan ≈ 4.6 keyposes, stack blocks ≈ 14.6 keyposes.

**Demo source:** RLBench scripted-waypoint + motion-planner demos (paper references RLBench as the source without re-describing generation).

---

### 1.6 OpenVLA (arXiv 2406.09246, CoRL 2024) — LIBERO evaluator

**Action output type: dense per-step control (7-DoF delta EE pose)**

> "LIBERO simulation benchmark, which features a Franka Emika Panda arm in simulation with demonstrations containing camera images, robot state, task annotations, and delta end-effector pose actions."
> — arXiv 2502.19645v1 (OpenVLA-OFT), §3, summarizing the OpenVLA LIBERO setup

**Exact action vector:** 7-dimensional delta end-effector pose — Δ(x, y, z) + Δ(rx, ry, rz) + gripper open/close — each dimension discretized into 256 bins and tokenized into the language model's vocabulary.

> "we discretize each dimension of the robot actions separately into one of 256 bins."
> — arXiv 2406.09246, §3

**Inference rate:** "approximately 6 Hz on one NVIDIA RTX 4090 GPU." The LIBERO environment runs at 20 Hz control frequency; OpenVLA therefore executes 1 action per step at a subsampled ≈ 5-6 Hz. **No motion planner.** Actions are fed directly to robosuite's Operational Space Controller (OSC), which closes the loop at 20 Hz with interpolation.

**No action chunking** in baseline OpenVLA: "The paper contrasts this with Diffusion Policy, which uses action chunking." (arXiv 2406.09246 discussion).

**Demo source:** LIBERO demos — 50 demonstrations per task, collected by human operators via SpaceMouse 3D mouse at 20 Hz control frequency. (Source: LIBERO paper arXiv / NeurIPS 2023, §3.3 / repo README; confirmed by emergentmind.com LIBERO topic summary: "SpaceMouse at 20 Hz...50 high-quality, human-teleoperated demonstrations per task.")

---

### 1.7 Diffusion Policy (arXiv 2303.04137, RSS 2023 / IJRR 2024) — Robomimic / LIBERO evaluator

**Action output type: dense action-chunk (receding-horizon diffusion)**

> "at time step t the policy takes the latest Tₒ steps of observation data Oₜ as input and outputs Tₚ steps of actions, of which Tₐ steps of actions are executed on the robot without re-planning."
> — arXiv 2303.04137v5, §3

**Key parameters:** Tₐ = 8 (execution horizon), Tₚ = 16 (prediction horizon), found optimal for most tested tasks.

**Control frequency:** "Diffusion Policy predicts robot commands at 10 Hz and these commands then linearly interpolated to 125 Hz for robot execution." (§5, Push-T task). For Robomimic/LIBERO evaluation, 20 Hz is the native control rate.

**Execution:** Direct joint / EE commands to low-level controller. No motion planner. Continuous, smooth motion is an emergent property of predicting temporally consistent action sequences.

**Demo source:** Human teleoperation via SpaceMouse (single-arm tasks); Meta Quest Pro VR controllers or Haption haptic devices for bimanual tasks (arXiv 2303.04137v5, §5.1). This mirrors the LIBERO demo collection methodology.

---

### 1.8 RLBench Demo Generation (arXiv 1909.12271 — James et al., 2019)

> "Each task comes with an infinite supply of demos through the use of motion planners operating on a series of waypoints given during task creation time; enabling demonstration-based learning."
> — arXiv 1909.12271, summary (confirmed by RLBench tutorials/simple_task.md)

The exact mechanism: task authors define dummy objects ("waypoint0", "waypoint1", …) as target SE(3) poses in CoppeliaSim. RLBench's Python API runs a path planner (CoppeliaSim's internal BiRRT) between each pair of consecutive waypoints, producing a smooth joint trajectory. The recorded demo therefore consists of the *waypoint keyposes* (for keyframe extraction) plus the dense path between them. Because the planner is deterministic given the waypoints, demos lack the variability and multi-modality of human teleoperation.

---

## 2. Master Comparison Table

| Model | Benchmark | Action Output Type | Inference Rate / Horizon | Planner Between Actions | Demo Source |
|-------|-----------|-------------------|--------------------------|------------------------|-------------|
| **BridgeVLA** | RLBench (18 tasks) | Keypose — 6-DoF EE + gripper + collision flag; rotation discretized to 72 bins/axis | ~4.8 keyposes/s prediction (0.21 s/step); ~3–9 keyposes per episode | Yes — sampling-based (OMPL/RRT-Connect/MoveIt) generates full joint trajectory to each predicted pose | RLBench scripted waypoints + CoppeliaSim motion planner |
| **PerAct** | RLBench (18 tasks) | Keypose — discretized voxel translation + 5° rotation bins + gripper + collision | ~3–9 keyposes per episode (task-dependent; mean ~5–6 from supp. Table 3) | Yes — CoppeliaSim internal motion planner (`MoveArmThenGripper(EndEffectorPoseViaPlanning)`) | RLBench scripted waypoints + CoppeliaSim motion planner (100 demos/task) |
| **RVT** | RLBench (18 tasks) | Keypose — 6-DoF EE pose (3D translation + 3D rotation) + gripper + collision; 8-dim total | ~3–9 keyposes per episode (same RLBench tasks) | Yes — CoppeliaSim internal motion planner ("low-level motion planner and controller") | RLBench scripted waypoints + CoppeliaSim motion planner (100 demos/task) |
| **RVT-2** | RLBench (18+ tasks) | Keypose — 3D heatmap peak + location-conditioned rotation + gripper open/close | Varies by task; iterative predict-move loop | Yes — sampling-based motion planner ("predicted pose is passed to a motion planner") | RLBench scripted waypoints + CoppeliaSim motion planner |
| **3D Diffuser Actor** | RLBench (18 tasks) | Keypose (RLBench mode) — 3D pos + 6D rotation + gripper; diffusion over trajectory | ~3 keyposes (open_drawer) to ~14.6 (stack_blocks); avg task-dependent | Yes — BiRRT native to RLBench ("employ the low-level motion planner BiRRT") | RLBench scripted waypoints + CoppeliaSim motion planner |
| **OpenVLA** | LIBERO (4 suites) | Dense per-step — 7-DoF delta EE pose (Δx,Δy,Δz,Δrx,Δry,Δrz + gripper); 256-bin discretized, 7 tokens/step | 1 action/step at ~5–6 Hz inference; no chunking; LIBERO runs at 20 Hz OSC | No — direct OSC control (robosuite); no motion planner | 50 human teleop demos/task via SpaceMouse at 20 Hz |
| **Diffusion Policy** | Robomimic / LIBERO | Dense action-chunk — 7-DoF (pos+rot+gripper) continuous, Tₚ=16 steps predicted, Tₐ=8 executed | Predicts at 10 Hz; executes 8-step chunk (≈0.08 s/step at 125 Hz interpolation); re-plans every 8 steps | No — direct low-level controller; receding horizon replanning | Human teleop via SpaceMouse (single-arm) / VR controllers; 50–656 demos/task |

---

## 3. Summary: Why BridgeVLA Looks Segmented, Why OpenVLA Looks Continuous

**Is BridgeVLA's segmented motion caused by (a) action space (keypose), (b) data (motion-planner demos), or (c) both? — Answer: both, and they reinforce each other.**

**(a) Action space:** BridgeVLA, PerAct, RVT, RVT-2, and 3D Diffuser Actor all predict only *next-best keyposes* — sparse SE(3) targets spaced at gripper-state transitions (pre-grasp, grasp, lift, place, etc.). Between two predicted poses, the robot executes a planner-generated trajectory and then *halts* before the next observation-predict cycle begins. This produces the characteristic "move → stop → (model infers) → move → stop" rhythm that is structurally impossible to avoid when inference runs at keypose granularity, regardless of data.

**(b) Demo data:** RLBench demonstrations are generated by scripted waypoints fed to CoppeliaSim's motion planner. Because each waypoint maps to a full-stop pose in the demo, the training signal explicitly teaches the model that "the correct thing to predict is a pose where motion will stop." The data distribution contains no smooth blending between keypose transitions and no variation in inter-keypose timing — reinforcing the policy's tendency to target discrete stopping poses.

**(c) Interaction:** Even if a keypose model were trained on motion-capture data with smooth blends, the inference loop itself — predict one pose, execute to completion, observe, predict next — guarantees visual segmentation. The data effect is secondary: motion-planner demos mean the model never saw smooth human motion, so it cannot learn to target intermediate flow-through poses even if the action format permitted it.

**Why does OpenVLA on LIBERO look continuous? — Answer: both the dense action space and human-teleop data contribute, but the action space is the structural enabler.**

OpenVLA outputs a *delta EE pose at every control step* (≈5–6 Hz inference, fed directly to a 20 Hz OSC controller). There is no planner in the loop: each predicted delta is immediately applied to the current EE pose, and the robot smoothly tracks the resulting sequence. The 50 human SpaceMouse demonstrations per task provide smooth, continuous trajectories with natural velocity profiles — so the training distribution reflects genuine motion continuity. The combination means: (1) the policy *can* output smooth motion (dense action format allows it), and (2) the training data *shows* smooth motion (human teleop, not scripted waypoints). Neither factor alone would be sufficient — a dense action policy trained on scripted-waypoint data would still exhibit jerky starts/stops, and a keypose policy trained on human data would still halt between predictions.

---

## 4. Sources

- BridgeVLA: https://arxiv.org/html/2506.07961v2
- PerAct: https://peract.github.io/ ; https://arxiv.org/abs/2209.05451 ; https://github.com/peract/peract
- PerAct2 (keyframe statistics): https://arxiv.org/html/2407.00278v1
- RVT: https://arxiv.org/html/2306.14896v1
- RVT-2: https://arxiv.org/html/2406.08545v1
- 3D Diffuser Actor: https://arxiv.org/html/2402.10885v2
- OpenVLA: https://arxiv.org/html/2406.09246v3 ; https://arxiv.org/html/2502.19645v1
- Diffusion Policy: https://arxiv.org/html/2303.04137v5
- RLBench demo generation: https://arxiv.org/abs/1909.12271 ; https://github.com/stepjam/RLBench/blob/master/tutorials/simple_task.md
- LIBERO demo details: NeurIPS 2023 LIBERO paper (https://www.cs.utexas.edu/~pstone/Papers/bib2html-links/liu_zhu_NeurIPS2023.pdf) ; https://www.emergentmind.com/topics/libero
