# RLBench Demo Pipeline — Motion Smoothness Investigation

**Date:** 2026-05-21  
**Source repo:** `/home/theo_lab/RLBench_docker`

---

## 1. Demo Generation Pipeline

### Mechanism: Scripted waypoints + CoppeliaSim path planner (RRTConnect)

Demos are **not** human teleoperated, RL-generated, or PDDL-planned.  
They are generated automatically by executing a **scripted sequence of Dummy-object waypoints** placed in the CoppeliaSim scene per task, with motion between waypoints planned on-the-fly using **CoppeliaSim's built-in RRTConnect planner** (exposed via PyRep).

**Entry point:** `rlbench/dataset_generator.py`

```python
# dataset_generator.py:192-198
rlbench_env = Environment(
    action_mode=MoveArmThenGripper(JointVelocity(), Discrete()),
    ...
    headless=True)
...
demo, = task_env.get_demos(amount=1, live_demos=True)
```

**Core loop:** `rlbench/backend/scene.py:323-453` — `get_demo()`

```python
# scene.py:335-376 (condensed)
waypoints = self.task.get_waypoints()
for i, point in enumerate(waypoints):
    point.start_of_path()
    path = point.get_path()          # RRTConnect call
    done = False
    while not done:
        done = path.step()           # executes one sim step along path
        self.step()
        self._demo_record_step(demo, record, callable_each_step)
    point.end_of_path()
    # then actuate gripper if ext contains open_gripper()/close_gripper()
```

**Motion planner used:** `rlbench/backend/waypoints.py:55-62`

```python
# waypoints.py:55-62
path = arm.get_path(self._waypoint.get_position(),
                    euler=self._waypoint.get_orientation(),
                    ignore_collisions=...,
                    trials=100,
                    max_configs=10,
                    trials_per_goal=10,
                    algorithm=Algos.RRTConnect)
```

`Algos.RRTConnect` is `pyrep.const.ConfigurationPathAlgorithms.RRTConnect` — CoppeliaSim's built-in sample-based planner. For linear (Cartesian) paths, `arm.get_linear_path()` is used instead (IK-based straight-line path).

**Observation recording:** Every simulation step along each planned path segment is recorded (`_demo_record_step` at `scene.py:464-468`). Gripper actuations are only recorded if `obs_config.record_gripper_closing=True` (default: `False`, `observation_config.py:54`). So by default, gripper-closing frames are dropped — the demo jumps from "about to grasp" to "grasping complete."

---

## 2. Waypoint / Keypoint Structure

### Waypoints = discrete Dummy poses in the CoppeliaSim scene

**Discovery:** `rlbench/backend/task.py:371-415` — `_get_waypoints()`

```python
# task.py:371-393 (condensed)
waypoint_name = 'waypoint%d'
while True:
    name = waypoint_name % i       # waypoint0, waypoint1, ...
    if not Object.exists(name): break
    ob_type = Object.get_object_type(name)
    if ob_type == ObjectType.DUMMY:
        way = Point(waypoint, self.robot, ...)   # target pose
    elif ob_type == ObjectType.PATH:
        way = PredefinedPath(cartesian_path, self.robot)
```

Waypoints are **named Dummy objects** (`waypoint0`, `waypoint1`, ...) stored in the `.ttm` task model. Each carries:
- A 6-DOF target pose (position + orientation)
- An optional extension string (e.g. `"open_gripper()"`, `"close_gripper()"`, `"ignore_collision"`, `"linear"`)

Task `init_episode()` repositions these Dummies for each randomized variation:

```python
# close_jar.py:29-31
w3 = Dummy('waypoint3')
w3.set_orientation([-np.pi, 0, -np.pi], reset_dynamics=False)
w3.set_position([0.0, 0.0, 0.125], relative_to=self.jars[index % 2], ...)
```

Waypoints are **discrete goal poses**, not dense trajectories. The planner synthesizes a smooth joint-space trajectory between consecutive waypoints, but only the start and end poses are specified by the task author. Typical tasks have 4–8 waypoints.

---

## 3. Action Modes Available at Inference Time

All action modes are in `rlbench/action_modes/`:

### Arm Action Modes (`arm_action_modes.py`)

| Class | Type | Mechanism |
|---|---|---|
| `JointVelocity` | **Direct** | Sets joint target velocities; single `scene.step()` |
| `JointPosition` | **Direct** | Sets joint target positions (abs or delta); single `scene.step()` |
| `JointTorque` | **Direct** | Sets joint torques; single `scene.step()` |
| `EndEffectorPoseViaPlanning` | **Planner-mediated** | Calls RRTConnect; loops `path.step()` until done |
| `EndEffectorPoseViaIK` | **Planner-mediated (IK)** | Solves IK via Jacobian; loops `scene.step()` until converged |
| `ERJointViaIK` | **Planner-mediated (IK+constraint)** | IK with locked joints; loops `scene.step()` |

### Composite Action Modes (`action_mode.py`)

| Class | Description |
|---|---|
| `MoveArmThenGripper` | Applies arm action, **then** gripper action sequentially |
| `JointPositionActionMode` | Delta joint pos + abs gripper, in single `scene.step()` |

### Planner-Mediated vs. Direct

- **Planner-mediated** (`EndEffectorPoseViaPlanning`): action = target EE pose → plan full collision-free path → execute all steps in simulation → return. From the policy's perspective, one `step()` call blocks until arm arrives. See `arm_action_modes.py:227-280`:

```python
# arm_action_modes.py:255-280
path = scene.robot.arm.get_path(
    action[:3], quaternion=action[3:],
    algorithm=Algos.RRTConnect
)
done = False
while not done:
    done = path.step()
    scene.step()
    success, terminate = scene.task.success()
    if success: break
```

- **Direct** (`JointPosition`, `JointVelocity`): action is applied immediately and only a **single** `scene.step()` is called per policy step. No internal planning loop.

### Default Action Mode in RLBench Benchmarks

The standard used in the original RLBench paper and dataset generator is `MoveArmThenGripper(JointVelocity(), Discrete())` (`dataset_generator.py:193`). However, **3D-keypose papers** (PerAct, RVT, BridgeVLA) use `MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())`, matching the keyframe-based action space.

---

## 4. Control Rate / Step Frequency

- **Simulation timestep:** `_DT = 0.05` seconds (20 Hz) — `task_environment.py:18`
- **`STEPS_BEFORE_EPISODE_START = 10`** — lets objects settle before demo (`scene.py:22,149`)
- **`_MAX_DEMO_ATTEMPTS = 10`** — retries per demo if planning fails (`task_environment.py:20`)
- **Recording granularity:** every simulation step along each waypoint path. Each `path.step()` advances CoppeliaSim by one timestep. `_demo_record_step` appends an observation at **every sim step** (`scene.py:464-468`). Gripper-closing steps are NOT recorded by default (`record_gripper_closing=False`).
- Demos therefore contain dense observations (all path steps), but the gripper transition is a hard cut.

---

## 5. Keyframe Extraction Utilities

**RLBench itself has no keyframe extraction code.** A search for `keyframe`, `keypoint`, `demo_to_keyframe` across all `.py` files in the repo (excluding submodule repos) returns zero results.

Keyframe/keypoint extraction for papers like PerAct, RVT, and BridgeVLA lives **downstream** — in those papers' own training code. They load the full dense demo, then sub-sample to "waypoint frames" (typically: the observation at the end of each planner segment, i.e. just before a gripper action changes).

The `Demo` class (`rlbench/demo.py`) is a plain list of `Observation` objects with no built-in keyframe logic:

```python
# demo.py:6-11
class Demo(object):
    def __init__(self, observations: List[Observation], ...):
        self._observations = observations
    def __len__(self): return len(self._observations)
    def __getitem__(self, i) -> Observation: return self._observations[i]
```

---

## 6. Eval Rollout Motion — Why It Looks "Segmented"

### For `MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())`

This is the action mode used by all 3D-keypose imitation learning papers (PerAct, RVT, BridgeVLA). The code path per policy step is:

1. **Policy outputs** a 7-D target EE pose (x, y, z, qx, qy, qz, qw) + binary gripper.
2. **`MoveArmThenGripper.action()`** is called (`action_mode.py:37-42`):
   - Calls `arm_action_mode.action(scene, arm_action)` → `EndEffectorPoseViaPlanning.action()`
   - This **blocks** the Python thread and runs the RRTConnect planner + full execution loop
   - After arm fully arrives, calls `gripper_action_mode.action(scene, ee_action)` → `Discrete.action()`
   - This **blocks** again until gripper fully opens/closes (with extra 10 steps for object drop, `gripper_action_modes.py:85`)
3. **Control returns to the policy**, which makes the next inference call.

This produces a **hard stop → plan → execute → stop → gripper actuation → stop → infer** cycle for every prediction. The robot is **never moving continuously**; it executes one planned segment, arrives at rest, then waits for the next policy action.

**Concretely:**

```python
# action_mode.py:37-42
def action(self, scene: Scene, action: np.ndarray):
    arm_act_size = np.prod(self.arm_action_mode.action_shape(scene))
    arm_action = np.array(action[:arm_act_size])
    ee_action = np.array(action[arm_act_size:])
    self.arm_action_mode.action(scene, arm_action)   # blocks until done
    self.gripper_action_mode.action(scene, ee_action) # blocks until done
```

The full path execution is inside `EndEffectorPoseViaPlanning.action()` at `arm_action_modes.py:273-280` — a `while not done` loop that only returns control when the arm has reached the target.

### For `JointPosition` / `JointVelocity` (Direct Modes)

Each policy step applies the action and calls exactly one `scene.step()`. Control returns immediately. If the policy runs at the sim rate (20 Hz), motion can be continuous. The "segmented" appearance does NOT occur in these modes unless the policy itself is slow.

### Root Cause of Segmented Motion

The segmented visual appearance in eval rollouts is **primarily an artifact of the action mode**, not the planner quality or data distribution:

1. `EndEffectorPoseViaPlanning` serializes arm + gripper execution, creating full stops between actions.
2. 3D-keypose models are trained on **keyframe observations** (one per waypoint), so they learn to predict discrete poses — they are never trained to output dense continuous control.
3. Even if the planner generates a smooth internal path, the **policy's output rate** is 1 Hz or lower (inference time), so the robot stops completely between predictions.

The data distribution reinforces this: demos are stored at every sim step, but downstream training filters to keyframes, so the model never sees (and is never trained to produce) inter-waypoint observations.

---

## Summary

| Question | Answer |
|---|---|
| Demo generation mechanism | Scripted Dummy waypoints per task; CoppeliaSim RRTConnect planner connects them; `scene.get_demo()` executes each segment step-by-step |
| Planner | CoppeliaSim built-in RRTConnect (via `pyrep.const.ConfigurationPathAlgorithms.RRTConnect`) |
| "Segmented" action mode | `MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())` |
| Why segmented | Each policy call blocks until the full planned path executes, then gripper actuates to completion — full stop between every action |
| Cause | Action mode design (planner-mediated, blocking execution); reinforced by keyframe-only training data |
| Keyframe extraction | Not in RLBench; lives in downstream training code (PerAct, RVT, BridgeVLA) |
