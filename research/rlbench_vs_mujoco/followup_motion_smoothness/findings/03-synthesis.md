# 왜 RLBench의 BridgeVLA는 뚝뚝 끊기고, LIBERO의 OpenVLA는 연속적인가

**Date:** 2026-05-21
**Synthesizes:** `findings/01-rlbench-demo-pipeline.md`, `findings/02-model-action-spaces.md`

---

## 1. 한 줄 답

끊김의 **주원인은 action space 차이**다 — BridgeVLA(류)는 "다음 keypose 하나"를 예측하고 그 사이를 motion planner가 채우는 *predict-plan-stop-predict* 루프이고, OpenVLA는 매 step delta-EE를 직접 controller에 흘려보내는 dense closed-loop이다. 데이터 출처(scripted waypoint vs 사람 SpaceMouse teleop)는 이 차이를 **강화**하는 보조 요인이다.

---

## 2. 두 축으로 나눠 보기 — Action Space × Demo Data

| 축 | RLBench + BridgeVLA(류: PerAct/RVT/RVT-2/3D Diffuser Actor) | LIBERO + OpenVLA(류: Diffusion Policy) |
|----|---|---|
| **액션 출력 단위** | keypose 1개: 6-DoF EE pose + gripper + collision flag [findings/02 §1.1, §1.3] | 7-DoF delta EE pose (Δx,Δy,Δz,Δrx,Δry,Δrz + gripper), 매 step [findings/02 §1.6] |
| **rotation 표현** | 이산화 (BridgeVLA 72 bins/axis; PerAct 5° bins; RVT 8-dim) [findings/02 §1.1–1.3] | 256 bins/dim, 토큰화 [findings/02 §1.6] |
| **평가 시 액션 사이** | `MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())` — RRTConnect로 trajectory 합성 → arm 도착할 때까지 **blocking** → 그 다음 gripper도 blocking [findings/01 §3, §6] | OSC controller에 직접 들어감, 20 Hz로 interpolation, planner 없음 [findings/02 §1.6] |
| **데모 데이터 출처** | scripted Dummy waypoint + CoppeliaSim RRTConnect planner (자동 생성) [findings/01 §1, §2] | 50 SpaceMouse 사람 teleop @ 20 Hz [findings/02 §1.6] |
| **데모 frame 처리** | 다운스트림(PerAct/RVT/BridgeVLA)에서 keyframe sub-sampling — RLBench 자체에는 keyframe 코드 없음 [findings/01 §5] | 20 Hz 그대로 사용 [findings/02 §1.6] |
| **제어 주파수 (eval)** | inference ~4.8 Hz × episode당 3–9 keyposes; 각 step은 planner 완주 시간 + 10 step gripper settle [findings/02 §1.1; findings/01 §6] | inference ~5–6 Hz → 20 Hz OSC가 보간 [findings/02 §1.6] |
| **결과 모션** | "predict → plan → move-to-stop → gripper-to-stop → predict" 사이클, 매 prediction 사이 **완전 정지** [findings/01 §6] | dense control loop, 멈춤 없음 [findings/02 §3] |

---

## 3. 인과 분해 — 무엇이 주원인이고 무엇이 강화 요인인가

### 주원인: Action space (keypose vs dense)

- BridgeVLA의 inference loop 자체가 "1) predict keypose 𝐚ₜ, 2) move to predicted keyframe pose Tₜ using a sampling-based motion planner" [findings/02 §1.1 인용]. 한 step의 의미가 "다음 정지 위치 1개"이므로 **policy 호출 사이에 robot은 구조적으로 정지**한다.
- `MoveArmThenGripper.action()`이 arm 도착까지 blocking하고, 이어서 gripper actuation도 blocking으로 완주한다 — 코드 레벨에서 stop-execute-stop이 강제됨 [findings/01 §3, §6의 `action_mode.py:37-42`, `arm_action_modes.py:273-280`].
- OpenVLA는 반대로 "7-dimensional delta end-effector pose...fed directly to robosuite's Operational Space Controller (OSC), which closes the loop at 20 Hz with interpolation" — planner가 없다 [findings/02 §1.6 인용].

### 강화 요인: Demo data 출처

- RLBench 데모는 "scripted Dummy waypoints + CoppeliaSim RRTConnect planner" 자동 생성 [findings/01 §1; findings/02 §1.8 인용 "infinite supply of demos through the use of motion planners operating on a series of waypoints"]. **각 waypoint가 정지 pose**이므로 training signal이 "정지 pose를 맞추는 것"이 됨 [findings/02 §3-(b)].
- 추가로 PerAct/RVT/BridgeVLA는 dense demo를 받은 뒤 **gripper 상태가 바뀌는 시점의 keyframe만 추출**해서 학습 (RVT-2의 "when the state of the gripper changes between open and close, the pose is a key-frame pose" [findings/02 §1.4 인용]). 모델은 inter-waypoint 관측을 본 적도, 만들어본 적도 없음 [findings/01 §6].
- LIBERO 데모는 "50 demonstrations per task, collected by human operators via SpaceMouse 3D mouse at 20 Hz" — 자연스러운 velocity profile이 그대로 학습 데이터에 들어감 [findings/02 §1.6 인용].

### 반사실 (counterfactual)

- **BridgeVLA를 사람 teleop 데이터로 학습시켜도 끊김은 그대로** — inference granularity가 keypose이므로 "predict-plan-stop" 루프는 데이터와 무관하게 유지됨 [findings/02 §3-(c) 인용 "Even if a keypose model were trained on motion-capture data with smooth blends, the inference loop itself — predict one pose, execute to completion, observe, predict next — guarantees visual segmentation"].
- **OpenVLA를 scripted-waypoint 데이터로 학습시키면 dense format 덕에 형태는 유지되지만 jerky해질 수 있음** — "a dense action policy trained on scripted-waypoint data would still exhibit jerky starts/stops" [findings/02 §3 마지막 단락 인용]. 데이터의 velocity profile이 부드러움의 *질*을 결정함.
- 즉 **action space는 끊김의 on/off 스위치**, **데이터는 부드러움의 dimmer**.

---

## 4. 코드/논문 근거 (인용 모음)

### Action space 측 (주원인)

- BridgeVLA iterative keypose loop: "predicting the action 𝐚ₜ...moving to the predicted next keyframe pose Tₜ using a sampling-based motion planner" [findings/02 §1.1]
- PerAct: "outputs discretized actions by detecting the next best voxel action...executed with a motion-planner" [findings/02 §1.2]
- RVT: "predicts a target end-effector pose and gripper state at the next key-frame" [findings/02 §1.3]
- RVT-2: "The predicted pose is then passed to a motion planner, which generates a trajectory towards it" [findings/02 §1.4]
- 3D Diffuser Actor (RLBench mode): "employ the low-level motion planner BiRRT, native to RLBench, to reach the predicted pose" [findings/02 §1.5]
- OpenVLA dense delta EE: "7-dimensional delta end-effector pose...each dimension discretized into 256 bins" [findings/02 §1.6]
- OpenVLA no planner: "No motion planner. Actions are fed directly to robosuite's Operational Space Controller (OSC)" [findings/02 §1.6]

### RLBench 코드 레벨 (blocking 동작)

- `EndEffectorPoseViaPlanning.action()`의 blocking `while not done: done = path.step(); scene.step()` 루프 [findings/01 §3, `arm_action_modes.py:255-280`]
- `MoveArmThenGripper.action()`의 arm-then-gripper 직렬 실행: "arm_action_mode.action(...) → blocks until done; gripper_action_mode.action(...) → blocks until done" [findings/01 §3, `action_mode.py:37-42`]
- gripper actuation 후 추가 10 step settle: [findings/01 §6, `gripper_action_modes.py:85`]
- "The robot is **never moving continuously**; it executes one planned segment, arrives at rest, then waits for the next policy action" [findings/01 §6]

### Demo data 측 (강화 요인)

- RLBench 데모: scripted Dummy waypoints + CoppeliaSim RRTConnect, `rlbench/backend/scene.py:323-453` [findings/01 §1]
- "infinite supply of demos through the use of motion planners operating on a series of waypoints" [findings/02 §1.8, James et al. 2019 인용]
- 각 task당 100 demos, planner-deterministic: "demos lack the variability and multi-modality of human teleoperation" [findings/02 §1.8]
- LIBERO: "50 high-quality, human-teleoperated demonstrations per task" via SpaceMouse @ 20 Hz [findings/02 §1.6]
- 데이터의 인과적 역할: "the data distribution contains no smooth blending between keypose transitions" [findings/02 §3-(b)]

### Keyframe sub-sampling (RLBench 외부에서 일어남)

- "RLBench itself has no keyframe extraction code" — 다운스트림 (PerAct/RVT/BridgeVLA) training code에서 처리 [findings/01 §5]
- RVT-2의 keyframe 정의 규칙: "when the state of the gripper changes between open and close, the pose is a key-frame pose" [findings/02 §1.4]

---

## 5. 사용자 후속 질문 대비 — 자주 묻는 변형

### Q1. "RLBench에서도 dense control로 학습하면 부드러워지나?"

**부분적으로 가능.** RLBench는 `JointPosition` / `JointVelocity` / `EndEffectorPoseViaIK` 같은 **direct action mode**를 제공하고, 이 모드들은 "action is applied immediately and only a single `scene.step()` is called per policy step" [findings/01 §3]. 즉 dense closed-loop이 구조적으로 가능.

다만 두 가지 caveat:
- RLBench 데모 자체가 RRTConnect planner의 출력이므로 **velocity profile이 사람 teleop 같지 않음** — 가속/감속이 planner 휴리스틱에 따라 결정됨 [findings/02 §1.8].
- 다운스트림 keyframe sub-sampling을 안 하고 dense 20 Hz로 학습해야 함 (PerAct/RVT/BridgeVLA 학습 코드의 sub-sampling 단계를 끄면 됨) [findings/01 §5].

### Q2. "BridgeVLA가 LIBERO에서 평가되면 부드러워질 수 있나?"

**액션 헤드가 그대로면 아니오.** BridgeVLA가 출력하는 건 "next keyframe pose Tₜ" 하나이고, 이걸 motion planner가 받아 처리하는 구조 [findings/02 §1.1]. LIBERO가 OSC controller를 쓴다고 해도, BridgeVLA의 출력 한 개를 "도착 목표"로 해석해서 OSC에 단발성으로 넘기면 마찬가지로 *stop-predict-stop*이 됨. **부드럽게 만들려면 action head를 dense delta-EE로 교체하고 RLBench 데모를 sub-sampling 없이 다시 학습해야 함**.

### Q3. "그럼 dense action + scripted-waypoint 데이터 조합은?"

[findings/02 §3 마지막 단락]에 직접 인용: "a dense action policy trained on scripted-waypoint data would still exhibit jerky starts/stops." 즉 형태(끊김 없음)는 살아나지만 자연스러움(velocity profile)은 떨어짐. 진짜 부드러운 모션은 dense action space + 사람 teleop 데이터의 **곱**으로 나옴.
