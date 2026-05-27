# RLBench vs MuJoCo-based 로봇 학습 벤치마크 비교

> **Scope.** RLBench (CoppeliaSim) 대 오픈소스 물리 기반 매니퓰레이션 벤치마크 4종 — LIBERO / Robosuite / Meta-World (MuJoCo) + ManiSkill (SAPIEN+PhysX). 모든 사실은 `findings/*.md`에 근거한다. 충돌 시 `30-audit-divergences.md` 와 `30-audit-consistency.md` 의 판정을 우선 적용한다.
>
> **Note on "MuJoCo-based" framing.** 원 프롬프트는 ManiSkill을 MuJoCo 진영으로 묶었으나, ManiSkill 2/3 은 **SAPIEN + PhysX** 기반이다 (MuJoCo 아님). 본 문서는 "MuJoCo 진영" = LIBERO + Robosuite + Meta-World, "SAPIEN 진영" = ManiSkill 로 분리해서 다룬다. `[ref: findings/30-audit-completeness.md §3, findings/30-audit-divergences.md D12]`

---

## 0. TL;DR

- **시뮬레이터/headless 운영 난이도:** RLBench(CoppeliaSim 4.1.0 Edu pin + Xvfb + `QT_PLUGIN_PATH` hack)이 가장 무겁다. LIBERO/Robosuite/Meta-World 는 MuJoCo EGL native, ManiSkill 3 은 Vulkan 의존이지만 GPU-parallel. `[ref: findings/10-source-01-rlbench.md §1,§7; findings/10-source-02-libero.md §7]`
- **VLA 채택:** 2024–2025 generalist VLA 의 사실상 표준은 **LIBERO**. RLBench 는 PerAct→RVT→RVT-2→3D Diffuser Actor→BridgeVLA 의 3D-manipulation 계열에서 dominant 하지만 OXE-pretrained 진영에서는 사실상 부재. `[ref: findings/10-source-04-vla-adoption.md §Trends]`
- **속도/병렬화:** GPU-parallel sim+render(30k+ FPS RGBD, RTX 4090 단일)이 필요하면 **ManiSkill 3** 이 유일한 옵션. RLBench/Robosuite/Meta-World/LIBERO 는 모두 1-env-per-process. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.3]`
- **씬 저작:** RLBench 만 GUI(CoppeliaSim 의 task builder) 필수. LIBERO 는 BDDL DSL, Robosuite 는 procedural Python+MJCF, Meta-World 는 hand-authored MJCF, ManiSkill 은 URDF/MJCF + Python. `[ref: findings/10-source-01-rlbench.md §2; findings/10-source-02-libero.md §2; findings/10-source-03-...md §A.2,§B.2,§C.2]`
- **언어 어노테이션:** RLBench 와 LIBERO 만 native NL 명령을 task definition 에 내장. Robosuite/Meta-World/ManiSkill 은 task 이름 또는 docs-level 만. `[ref: findings/10-source-01-rlbench.md §4; findings/10-source-02-libero.md §4]`
- **MuJoCo 라이선스:** **Apache 2.0** (October 2021). 자주 인용되는 "MIT" 는 잘못된 표기. `[ref: findings/30-audit-divergences.md D13]`
- **RLBench 태스크 수:** **paper 100 / repo HEAD 106** — 둘 다 사실, 단순 versioning. `[ref: findings/10-source-01-rlbench.md §8; findings/30-audit-divergences.md D1]`

---

## 1. 큰 그림 — 한 페이지 비교표

| 축 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| **물리 엔진** | CoppeliaSim 4.1.0 Edu (Bullet/ODE/Vortex/Newton/MuJoCo 선택 가능, 기본은 `.ttt` 임베디드) | MuJoCo (new `mujoco` binding, via Robosuite 1.4.0) | MuJoCo (new binding, v1.5 docs ≥2.3) | MuJoCo (≥2.3.3) | **SAPIEN + PhysX GPU** (MuJoCo 아님) |
| **라이선스 (sim)** | CoppeliaSim Edu — **비상업** | MuJoCo **Apache 2.0** | MuJoCo Apache 2.0 | MuJoCo Apache 2.0 | SAPIEN Apache 2.0; PhysX 상업 라이선스 필요 |
| **씬 포맷** | `.ttt` + `.ttm` (GUI 필수) | BDDL DSL + MJCF assets | MJCF XML (modular Python composer) | MJCF (hand-authored) | URDF + MJCF (Python class) |
| **태스크 수** | **100 (paper) / 106 (repo HEAD)** | 130 (10+10+10+90+10) | 9 표준 + 18 MimicGen | 50 (MT50/ML45) | 12 도메인 (총수 미공표) |
| **데모/태스크** | dataset_generator (변동) | 50/task | ~200 human (robomimic), 1k MimicGen 생성 | 없음 (RL only) | 백만+ frames (motion plan/RL/VR teleop) |
| **데모 포맷** | pickle(`List[Observation]`) + PNG | HDF5 (`{task}_demo.hdf5`) | HDF5 via robomimic | (없음) | HDF5 (`trajectory.{obs}.{ctrl}.{backend}.h5`) |
| **언어 어노테이션** | native, variation 별 multiple phrasings | native, `(:language ...)` in BDDL | task name only | task name only | task card text only |
| **로봇 종류** | 5 (Panda/Jaco/Mico/Sawyer/UR5) | Panda only | **10** (Panda/Sawyer/IIWA/Jaco/Kinova3/UR5e/Baxter/GR1/Spot/Tiago) — 7 arms + GR1 humanoid + Spot/Tiago mobile | Sawyer only | **20+** (Panda/UR5e/Xarm7/Sawyer/Jaco/Fetch/Stretch/AnyMAL-C/H1/G1/...) |
| **기본 카메라** | 5 (L/R shoulder, overhead, wrist, front) RGB+Depth+PointCloud+Mask | 2 (agentview, eye_in_hand) | configurable (`camera_names` list) | none default (state-based) | configurable multi-cam |
| **기본 해상도** | 128×128 | 128×128 | configurable | (image mode 보조) | configurable |
| **렌더링 백엔드** | CoppeliaSim OpenGL3 plugin (SW GLX/Xvfb) | MuJoCo native **EGL** (GPU offscreen) | MuJoCo **EGL** + 옵션 Isaac Sim photorealistic | MuJoCo EGL/GLFW | **SAPIEN Vulkan** (+ optional RT) |
| **headless 방식** | Xvfb + `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` (gotcha) | EGL, `MUJOCO_EGL_DEVICE_ID=GPU_ID`; X 불필요 | EGL native | EGL native | Vulkan + libvulkan1; WSL 미지원 |
| **GPU-parallel sim** | 없음 (1 proc/env) | SubprocVectorEnv (multi-proc) | 없음 (multi-proc only) | 없음 | **있음** — 30k+ FPS RGBD (RTX 4090), PickCube 128 envs ≈3.5 GB |
| **제어 주파수** | 20 Hz (`_DT=0.05`) | 20 Hz (`control_freq=20`) | 20 Hz default (sim ~500 Hz) | MuJoCo defaults (∼20 Hz 추정) | task-configurable |
| **액션 컨트롤러** | 6종 (JointVel/Pos/Torque, EE-via-Planning/IK, ERJointViaIK) + Discrete/JointPos gripper | OSC_POSE (3+3+1), OSC_POSITION fallback | **6종** (OSC_POSE, OSC_POS, IK_POSE, Joint{Pos/Vel/Torque}) + WBC v1.5 | 4-D EE delta + gripper | Joint pos/vel, EE pose/pos, GPU IK |
| **success metric** | binary per-step (`task.success()`) | binary per-episode (BDDL goal) | binary per-episode + Wiping % | binary per-episode | `success_once` / `success_at_end` |
| **표준 평가 protocol** | PerAct-18 (18 tasks × 249 var × 25 demos × 100 episodes) | 4 suites × 10 tasks × 50 demo × 20 rollouts × 600 steps; lifelong sequence (21 orderings) | robomimic train/val splits on Lift/Can/Square/Transport/ToolHang | MT1/MT10/MT50, ML1/ML10/ML45; IQM over 10 seeds | gymnasium-vec; success_once/at_end |
| **VLA 채택** | PerAct/RVT/RVT-2/3DDA/BridgeVLA | **OpenVLA, OpenVLA-OFT, Magma, π0/π0.5 post-pub ckpt, RoboFlamingo, MimicPlay, MUTEX, TAIL** | Diffusion Policy(robomimic) | (VLA 거의 없음, RL 전용) | TD-MPC2/RDT-1B baseline; SimplerEnv 가 MS2 기반 |
| **공식 Docker** | 본 리포 `docker/Dockerfile` (~6.6 GB) | 없음 | 없음 | 없음 | `maniskill/base` Docker Hub |
| **HF dataset 존재** | 없음 | `yifengzhu-hf/LIBERO-datasets` (~100 GB, 24k+ DL/mo); LeRobot 통합 | 없음 (robomimic 별도) | 없음 | 없음 (paper-scale teleop) |

`[refs: 위 표 전 행은 각각 findings/10-source-01-rlbench.md §1–§8, findings/10-source-02-libero.md §1–§8, findings/10-source-03-robosuite-metaworld-maniskill.md §A/§B/§C 전 섹션, findings/10-source-04-vla-adoption.md §A–K2 / §Summary Table 참조. 라이선스·VLA 채택 행은 findings/30-audit-divergences.md D4/D13/D16/D22 의 판정에 따라 보정함.]`

---

## 2. 축별 심층 비교

### 2.1 시뮬레이터 백엔드

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| 엔진 | CoppeliaSim 4.1.0 Edu | MuJoCo (new binding) | MuJoCo | MuJoCo ≥ 2.3.3 | SAPIEN + PhysX GPU |
| Python pin | **Python 3.8** 정확 매칭 | Python 3.8.13 | Python 3.x | Python 3.8–3.11 | (명시 X) |
| 라이선스 | Edu (비상업) | Apache 2.0 (MuJoCo) + MIT(code) + CC BY 4.0(data) | Apache 2.0 (MuJoCo) | Apache 2.0 (MuJoCo) | SAPIEN Apache 2.0; PhysX 상업 라이선스 |
| 제어 주파수 | 20 Hz | 20 Hz | 20 Hz | 20 Hz (추정) | task-configurable |
| 물리 sub-step | 50 ms ctrl / 5 ms dyn (200 Hz) | MuJoCo 기본 | sim_freq ≈ 500 Hz (25:1) | MuJoCo 1–2 ms 추정 | GPU sim batched |
| 결정성 | Cross-platform 비보장; `Demo.restore_state()` 는 `np.random` 만 복원 | MuJoCo 내부 결정 — fixed `.pruned_init` 으로 재현 | MuJoCo 결정적, seed 기반 | MuJoCo 결정적 | PhysX GPU 결정성 per-seed, bitwise cross-platform 비보장 |
| 측정 FPS | repo 에 미측정 (`benchmark_vector_step` runtime only) | 미공표 | 미공표 | 미공표 | **30,000+ FPS RGBD (RTX 4090)** |
| Headless | Xvfb 또는 nvidia-xconfig 또는 VirtualGL | EGL (X 불필요) | EGL Linux default | EGL Linux | Vulkan, libvulkan1 |

**시사점.**
- RLBench 만 sim 측 라이선스가 비상업적 (CoppeliaSim Edu). 다른 4종은 모두 오픈소스 진영. ManiSkill 의 PhysX 는 상업 사용 시 NVIDIA 라이선스가 별도 필요 — Isaac Gym/Lab 과 동일한 제약. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.7]`
- "MuJoCo 가 무료/오픈소스" 시점은 **2021년 10월**로 일치. 단 라이선스명은 **Apache 2.0** 이며 source-03 의 "MIT" 표기는 audit 에서 잘못된 것으로 확정됨. `[ref: findings/30-audit-divergences.md D13]`
- 측정 FPS 가 공식 보고된 것은 ManiSkill 3 (RTX 4090 RGBD 30k+) 뿐. 나머지는 "MuJoCo 가 CoppeliaSim 보다 빠르다" 가 정성적 주장으로만 존재한다. `[ref: findings/30-audit-completeness.md §2 items 2–3]`

---

### 2.2 씬/태스크 정의 방식

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| Master scene | `rlbench/task_design.ttt` (Coppelia) | MJCF arena XML (`scenes/libero_base_style.xml`) | Python-assembled MJCF tree | hand-authored MJCF | URDF/MJCF |
| Task atom | `.ttm` model + `.py` class | `.bddl` text + `InitialSceneTemplates` Python | `RobotEnv` subclass + procedural objects | MJCF + `SawyerEnv` subclass | `BaseEnv` subclass |
| 객체 라이브러리 | `rlbench/task_ttms/` ~107 모델 | LIBERO 자체 assets (akita black bowl, moka pot, ...) | `BoxObject` / `BallObject` / `CompositeObject` 등 procedural primitives + custom MJCF/STL | mujoco-menagerie Sawyer + 태스크별 단편 | 2000+ models (YCB/ShapeNet/PartNet-Mobility) in MS2 |
| GUI 필요? | **예 (필수)** — CoppeliaSim task builder | 아니오 | 아니오 | 아니오 | 아니오 |
| Waypoint 시스템 | `Dummy` 객체 `waypoint0..N` + ext field (`open_gripper()`/`close_gripper()`) | `(:init)` / `(:goal)` predicates (PDDL-style) | reward / termination Python | task-coded | task-coded |
| 변동 생성 | per-task `init_episode(index)` returns NL list | template + BDDL gen ("infinite") | random init + procedural objects | per-task | per-task |

**시사점.**
- RLBench 의 가장 큰 운영적 부담은 **GUI 의존**이다. 신규 task 추가 시 CoppeliaSim GUI 에서 `.ttm` 을 열어 waypoint 를 배치해야 한다 (`README.md:L380`). 이는 CI/cluster-only 환경에서는 사실상 불가능. `[ref: findings/10-source-01-rlbench.md §2]`
- LIBERO 는 BDDL DSL 로 task 를 텍스트 한 줄로 정의 + Python template 으로 "in principle infinite" 생성. RLBench 의 GUI 병목과 정반대. `[ref: findings/10-source-02-libero.md §2]`
- Robosuite 의 procedural composer (`Arena` + `MujocoObject` + `Task`) 는 두 진영의 중간 — Python 으로 다 짤 수 있지만 MJCF 트리를 직접 만지는 옵션도 열려 있다. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.2]`

---

### 2.3 렌더링 + GPU 가속 + 멀티프로세싱

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| 렌더 엔진 | CoppeliaSim OpenGL3 plugin (`libsimExtOpenGL3Renderer.so`) | MuJoCo native EGL | MuJoCo EGL (+옵션 Isaac Sim photorealistic) | MuJoCo EGL/GLFW | **SAPIEN Vulkan rasterizer** + 옵션 ray tracing |
| GPU 가속 (rendering) | 없음 (SW GLX/Xvfb 경로) | EGL → GPU offscreen | EGL → GPU offscreen | EGL → GPU | Vulkan GPU (parallel) |
| GPU 가속 (sim) | 없음 | MuJoCo 의 CPU sim | MuJoCo CPU sim | MuJoCo CPU sim | **PhysX GPU sim** (MS2 는 CPU-only, MS3 만 GPU sim) |
| 병렬 envs | gym vector async (spawn) — 1 CoppeliaSim proc/env | `SubprocVectorEnv` (20 default eval) | 외부 multi-proc (e.g. SubprocVecEnv) | 외부 multi-proc | **GPU-parallel**, single proc, thousands of envs |
| Multi-camera | 5 cam fixed + per-cam mask sensor | 2 cam (agentview, eye_in_hand) default | configurable list | 가능하나 미문서화 | configurable multi-cam |
| Modalities | RGB+Depth+PointCloud+Mask × 5 cam (per-step `obs.misc` 에 intrinsics/extrinsics) | RGB (+옵션 depth/seg) | RGB/Depth/Seg (instance/class/element)/proprio | state-only 우선; image 가능 | RGB/RGBD/PointCloud/Voxel/Seg |
| 메모리 (예시) | (미측정) | (미측정) | (미측정) | (미측정) | **PickCube 128 envs ≈ 3.5 GB GPU** (Isaac Lab 14.1 GB) |

**시사점.**
- RLBench 의 렌더링은 **CPU/software GLX** 위에서 돈다. GPU 는 ML inference 에만 쓰인다. `[ref: findings/10-source-01-rlbench.md §3]`
- `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` 가 빠지면 모든 카메라가 **all-zero black frames** 를 침묵으로 반환한다 (예외도 없음). 본 리포의 `docker/Dockerfile:L172` 가 이를 고정한다. `[ref: findings/10-source-01-rlbench.md §3, §7]`
- ManiSkill 3 의 진짜 차별점은 **sim + rendering 이 동시에 GPU-parallel** 이라는 점이다. PickCube 같은 state-based task 가 ~1 분에 학습된다 (MS2 CPU 대비 15× 가속). `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.3, §C.6]`

---

### 2.4 관측/액션 공간 + 데모 데이터 + 언어 어노테이션

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| 관측 형태 | dict (`Observation` dataclass): 5 cam × 4 mod + 7 joint scalars + EE pose/matrix + gripper + touch + `task_low_dim_state` + `misc` | dict: `agentview_image` 128³, `robot0_eye_in_hand_image` 128³, `robot0_gripper_qpos(2)`, `robot0_joint_pos(7)`, `robot0_eef_pos(3)`, `robot0_eef_quat(4)`, per-object | dict, modality+camera 키 — state, RGB, depth, seg, F/T, object poses 등 | 39-D state vector (EE pos + gripper + object pose×2 + quat, zero-padded); MT10/MT50 는 one-hot task ID 추가 | dict — `state` / `rgbd` / `pointcloud` / `state_dict`; `num_envs>1` 시 batched tensor |
| 액션 차원 | 컨트롤러별 — 7 (joint*), 7 (EE pose [x,y,z,qx,qy,qz,qw]), 1 (gripper Discrete) 등 | **7-D OSC_POSE** (Δx,Δy,Δz, axis-angle 3, gripper binary); fallback 4-D OSC_POSITION | 6 컨트롤러 (OSC_POSE/POSITION, IK_POSE, JointPos/Vel/Torque) + WBC v1.5 | **4-D** (Δx,Δy,Δz, gripper finger scalar) | Joint pos/vel, EE pose (delta), EE position; GPU-parallel IK via PyTorch Kinematics |
| 데모 포맷 | per-variation per-episode dir: pickled `List[Observation]` (`low_dim_obs.pkl`) + PNG per-step + `variation_descriptions.pkl` | **HDF5** per task (`{task}_demo.hdf5`), `data/demo_X/obs/{key}`, `actions`, `states`, `robot_states`, `rewards`, `dones`, `tag="libero-v1"` | **HDF5** via robomimic — raw `demo.hdf5` (state+action) → conversion script → obs added | **없음** — RL only (offline RL 시 scripted 또는 RL-generated 로 자체 생성) | **HDF5** (`trajectory.{obs_mode}.{control_mode}.{sim_backend}.h5` + JSON metadata) |
| 데모 스케일 | dataset_generator CLI 기반 (user-specified) | **50 demos/task** 모든 suite | ~200 human demos/task (robomimic canonical); MimicGen 으로 1k/task 생성 | (없음) | "Millions of frames" (motion plan/RL/VR teleop, MS2 4M+ frames) |
| 데모 수집 디바이스 | (스크립트 expert) | (스크립트 expert) | keyboard / SpaceMouse / DualSense / MuJoCo viewer drag-drop | n/a | motion planning, RL, VR (Meta Quest 3), RFCL/RLPD |
| 언어 어노테이션 | **native**, `init_episode(index) -> List[str]` per variation, multiple phrasings | **native**, `(:language ...)` in `.bddl`, single string per task | task name only (`"Lift"`, `"PickPlaceCan"`) | task name only (`"reach-v2"`) | task card text (docs-level) |
| 임베딩 | (downstream choice — PerAct uses CLIP) | BERT (`bert-base-cased`) default; GPT-2, CLIP, RoBERTa 옵션 | (downstream) | (n/a) | (downstream) |

**시사점.**
- **RLBench 관측 풍부도** 가 가장 높다 — 5 카메라 × {RGB, Depth, PointCloud, Mask} 가 매 스텝 동기화돼서 잡힌다. 3D 매니퓰레이션 모델 (PerAct, RVT, 3DDA, BridgeVLA) 이 RLBench 를 선호하는 핵심 이유. `[ref: findings/10-source-01-rlbench.md §3, §4]`
- **언어 어노테이션이 task definition 에 내장된 곳은 RLBench 와 LIBERO 둘뿐.** 다른 셋은 task 이름만 있다 → post-hoc CLIP 라벨링이 필요하다. `[ref: findings/10-source-01-rlbench.md §4; findings/10-source-02-libero.md §4; findings/10-source-03-...md §A.4, §B.4, §C.4]`
- **Meta-World 는 데모가 없다** — RL/meta-RL 전용. imitation/VLA 진영에서는 그대로 못 쓰는 구조. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.4]`
- 데모 포맷은 **RLBench 만 pickle+PNG**, 나머지는 HDF5. 이는 LeRobot/HuggingFace integration 의 장벽이 된다 (LIBERO 가 HF 24k+ DL/mo 인 이유 중 하나). `[ref: findings/10-source-02-libero.md §6]`

---

### 2.5 로봇 모델 + gripper/contact

| 항목 | RLBench | LIBERO | Robosuite v1.5 | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| 지원 arm 수 | **5** (Panda/Jaco/Mico/Sawyer/UR5) | **1** (Panda) | **10 (robots total; 7 tabletop arms + GR1 humanoid + Spot + Tiago mobile)** | **1** (Sawyer) | **20+** (Panda/UR5e/Xarm7/Sawyer/Jaco/Fetch/Stretch/AnyMAL-C/H1/G1/dexterous hands/floating gripper) |
| Bimanual | 없음 | 없음 | **있음** (Baxter 14-DoF) | 없음 | 있음 (RDT-1B baseline) |
| Mobile base | 없음 | 없음 | Omron Mobile Base, Spot Base | 없음 | Fetch, Stretch, AnyMAL-C, mobile bases |
| Humanoid | 없음 | 없음 | GR1 (24-DoF) | 없음 | Unitree H1, G1 |
| Gripper 종류 | 5 (Panda/Jaco/Mico/Baxter/Robotiq85) | PandaGripper | **9** (Panda, Robotiq 85/140, Robotiq3F, Rethink, Jaco3F, Inspire dex, BD, Wiping) | (Sawyer 기본) | 다양 + dexterous hands + floating gripper |
| Suction gripper | **없음** (`SUPPORTED_ROBOTS` 내 미정의) | 없음 | (별도) | 없음 | (없음 명시) |
| Contact 모델 | CoppeliaSim physics + **"grasp hack"** (rigid attach via `gripper.grasp(obj)`) | MuJoCo contact; table friction `(0.6, 0.005, 0.0001)` | MuJoCo contact + variable impedance + WBC | MuJoCo contact | PhysX GPU contact |
| Wrist 카메라 | 모든 지원 arm 의 `.ttm` 에 통합 필수 | `robot0_eye_in_hand` | configurable | configurable | configurable |
| Whole-body control | 없음 | 없음 | **v1.5 추가** (Composite WBC) | 없음 | 가능 (humanoid/quad) |

**시사점.**
- **embodiment 다양성: ManiSkill 3 ≫ Robosuite ≫ RLBench ≫ LIBERO ≈ Meta-World (1대).** humanoid/mobile/quadruped 까지 필요하면 ManiSkill 3 / Robosuite v1.5 만 옵션. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.5, §C.5]`
- RLBench 의 contact 는 **"grasp hack"** — `gripper.grasp(obj)` 호출 시 rigid attachment 가 강제로 생성된다. 연속 contact-force 시뮬레이션이 아니다. CloseJar 같이 회전 unscrew 가 있는 task 는 `base_rotation_bounds` 가 수동 튜닝돼 있다 ("issue occurred rarely so is only minor"). `[ref: findings/10-source-01-rlbench.md §5]`
- LIBERO 는 단일 embodiment (Panda) 만 — multi-arm/bimanual 베이스라인 비교용으로는 적합하지 않다. `[ref: findings/10-source-02-libero.md §5]`

---

### 2.6 생태계 (VLA/imitation 모델 채택 현황)

> **본 섹션은 `findings/10-source-04-vla-adoption.md` 가 paper-grounded 매트릭스이고, `findings/10-source-03-...md` 의 ecosystem 주장은 audit (D4/D16/D22) 에서 4건 hallucination 으로 확정됨. 따라서 source-04 매트릭스를 채택한다.** `[ref: findings/30-audit-divergences.md §2, findings/30-audit-consistency.md §1]`

#### 2.6.a Model × Benchmark 채택 매트릭스 (source-04 권위)

| Model | RLBench | LIBERO | Robosuite/Robomimic | Meta-World | ManiSkill | CALVIN | SimplerEnv | Real-only |
|---|---|---|---|---|---|---|---|---|
| OpenVLA | — | ✓ | — | — | — | — | — | — |
| OpenVLA-OFT | — | ✓ (97.1%) | — | — | — | — | — | — |
| RT-1 | — | — | — | — | — | — | — | ✓ |
| RT-2 | — | — | — | — | — | — | — | ✓ (Language-Table) |
| RT-X | — | — | — | — | — | — | — | ✓ |
| π0 (original paper) | — | — | — | — | — | — | — | ✓ |
| π0.5 (original paper) | — | — | — | — | — | — | — | ✓ |
| π0 / π0.5 post-pub ckpt | — | (✓, ckpt only) | — | — | — | — | — | — |
| Octo | — | — | — | — | — | — | — | ✓ |
| BridgeVLA | ✓ (88.2%) + COLOSSEUM (64.0%) + GemBench (50.0%) | — | — | — | — | — | — | — |
| GR00T N1 | — | — | — | — | — | — | — | ✓ (RoboCasa/DexMG/GR-1) |
| PerAct | ✓ (18 tasks, 249 var) | — | — | — | — | — | — | — |
| RVT | ✓ | — | — | — | — | — | — | — |
| RVT-2 | ✓ (82% from 65%) | — | — | — | — | — | — | — |
| Act3D | ✓ (74 tasks) | — | — | — | — | — | — | — |
| Diffusion Policy | — | — | ✓ (Robomimic) + Push-T, BET, Franka Kitchen | — | — | — | — | — |
| 3D Diffuser Actor | ✓ (+18.1%) | — | — | — | — | ✓ | — | — |
| CogACT | — | — | — | — | — | — | ✓ | — |
| Magma | — | ✓ | — | — | — | — | ✓ | — |
| RoboFlamingo | — | ✓ | — | — | — | — | — | — |
| MimicPlay | — | ✓ | — | — | — | — | — | — |
| MUTEX | — | ✓ | — | — | — | — | — | — |
| TAIL | — | ✓ | — | — | — | — | — | — |

`[ref: findings/10-source-04-vla-adoption.md §Summary Table; LIBERO 추가 모델은 findings/10-source-02-libero.md §6 의 RoboFlamingo/MimicPlay/MUTEX/TAIL 항목; D17 BridgeVLA 미평가 확인]`

#### 2.6.b 트렌드

| 트렌드 | 근거 |
|---|---|
| LIBERO 가 generalist VLA 의 de facto 표준 | LIBERO-PRO: "virtually all recent VLA studies report results on LIBERO"; vla-eval harness 3대 검증 벤치 중 하나 `[ref: findings/10-source-04-vla-adoption.md §LIBERO ranking]` |
| RLBench 는 3D-manipulation sub-field 에 dominant 하나 insular | PerAct→RVT→RVT-2→3DDA→BridgeVLA 전부 RLBench-only/-primary; OXE-pretrained 진영에서는 사실상 미사용 `[ref: findings/10-source-04-vla-adoption.md §Trends]` |
| 최대 generalist VLA 들이 simulation 평가를 안 한다 | π0, π0.5, Octo, RT-1, RT-X 모두 paper-reported sim eval = 0 `[ref: findings/10-source-04-vla-adoption.md §C, §D, §B]` |
| SimplerEnv (ManiSkill2/SAPIEN 기반) 가 중간 지점으로 부상 | CogACT, Magma 가 채택 — real-to-sim Google Robot / WidowX 재현 `[ref: findings/10-source-04-vla-adoption.md §K]` |
| Meta-World / ManiSkill 은 VLA paper 에서 거의 부재 | RL/sim-to-real 진영에서만 사용; VLA 표준 평가에는 미채택 `[ref: findings/10-source-04-vla-adoption.md §Trends 6]` |
| GR00T 는 자체 sim suite 를 만들었다 | RoboCasa, DexMG, GR-1 Tabletop — 기존 benchmark 미채택 `[ref: findings/10-source-04-vla-adoption.md §F, §Trends 5]` |

**중요 보정 (audit 권위):**
- "OpenVLA → robosuite eval" 주장은 hallucination. OpenVLA paper Appendix E 는 **LIBERO only**. `[ref: findings/30-audit-divergences.md D4]`
- "Octo → robosuite / ManiSkill3 eval" 주장도 hallucination. Octo paper §4 는 **real 9개 plat only**. ManiSkill3 가 Octo baseline implementation 을 제공 (paper eval ≠ shipped baseline). `[ref: findings/30-audit-divergences.md D22]`
- "Diffusion Policy → Meta-World / ManiSkill" 주장도 잘못. DP paper 의 4개 벤치는 **Robomimic, Push-T, BET-Block-Pushing, Franka Kitchen**. `[ref: findings/30-audit-divergences.md D16]`
- source-02 의 "CogACT → LIBERO" 주장은 source-04 (CogACT paper §4 = SimplerEnv only) 와 충돌. **CogACT 는 LIBERO 미평가** 가 정설. `[ref: findings/30-audit-divergences.md §2, findings/30-audit-consistency.md §1.2.source-02]`

---

### 2.7 설치·운영 (Docker/X server/headless)

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| Python pin | **3.8** 엄격 | 3.8.13 | 3.x | 3.8–3.11 | (미공개) |
| 핵심 dep pin | CoppeliaSim 4.1.0 Edu **고정** (newer = segfault); PyRep | robosuite==1.4.0, bddl==1.0.1, robomimic 0.2.0, PyTorch 1.11.0+cu113, transformers 4.21.1, gym 0.25.2 | (web docs 만; 자세한 pin 미공개) | `pip install metaworld`; Meta-World+ 권장 | `mani_skill` + torch + libvulkan1 |
| 설치 난이도 | **높음** — CoppeliaSim 600 MB binary + PyRep build + X 시스템 라이브러리 + X display | 중 — conda env + pip; 의존 버전 충돌이 주된 함정 | 낮음 — `pip install robosuite` | 낮음 — `pip install metaworld` (Meta-World+ 권장) | 중 — `pip install mani_skill` + Vulkan setup |
| X display 필요 | **예** — Xvfb 또는 X11 또는 VirtualGL | 아니오 (EGL native) | 아니오 (EGL native) | 아니오 (EGL native) | 아니오 (Vulkan native) |
| 핵심 env var | `LD_LIBRARY_PATH=$COPPELIASIM_ROOT`, `QT_QPA_PLATFORM_PLUGIN_PATH=$COPPELIASIM_ROOT/platforms`, **`QT_PLUGIN_PATH=$COPPELIASIM_ROOT`** | `MUJOCO_EGL_DEVICE_ID=GPU_ID` | (EGL 자동) | (EGL 자동) | `libvulkan1` 설치 |
| 공식 Docker | **본 리포** `docker/Dockerfile` (~6.6 GB, BridgeVLA variant 9 GB) | 없음 | 없음 | 없음 | **`maniskill/base`** Docker Hub |
| 알려진 break point | (1) `QT_PLUGIN_PATH` 누락 → all-zero frames (silent); (2) CoppeliaSim > 4.1.0 → segfault; (3) TF/LLVM clash → CoppeliaSim segfault (BridgeVLA); (4) PaliGemma HF gated weights; (5) BridgeVLA 12 GB VRAM 천장 (`select_feat_from_hm` 2 GiB int64); (6) YARR `_SimpleAccumulator.pop()` `>1` → `>=1` patch | (1) mujoco-py 와 new `mujoco` 혼동; (2) CUDA 11.3 pin (Ada Lovelace 충돌); (3) `transformers==4.21.1` old; (4) SubprocVectorEnv+EGL framebuffer 충돌 (retry 5×); (5) `bddl==1.0.1` 정확 매칭 | (web docs 만; 상세 미공개) | mujoco-py 의존 → Meta-World+ 로 교체; Windows CI 미지원 | Vulkan WSL 미지원; `vk::Instance::enumeratePhysicalDevices: ErrorInitializationFailed` |
| Windows | 아님 (Linux X 의존) | (Linux 위주) | macOS+Linux | Linux+macOS | CPU-only sim 만 (GPU 차단) |

`[refs: findings/10-source-01-rlbench.md §7; findings/10-source-02-libero.md §7; findings/10-source-03-...md §A.7,§B.7,§C.7]`

**시사점.**
- RLBench 의 install 은 **5종 중 가장 무겁다.** 본 리포의 commit `a19d62d9` (docker/standalone-setup) 는 정확히 이 문제를 해결한다 — `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` 한 줄이 black-frames 침묵 버그의 fix.
- LIBERO/Robosuite/Meta-World 의 install 부담은 비교적 낮으나 **공식 Docker 가 없는 게 공통 단점**이다. ManiSkill 만 공식 Docker 이미지를 Docker Hub 에 올려둔다.
- "MuJoCo 진영은 headless 가 native EGL 로 쉽다" 는 정성적으로 사실. 단 LIBERO 의 `SubprocVectorEnv+EGL framebuffer 충돌` (env 생성 retry 5회 가드) 같은 미세 함정은 존재한다. `[ref: findings/10-source-02-libero.md §7]`

---

### 2.8 평가 프로토콜 (task suite/metric/generalization)

| 항목 | RLBench | LIBERO | Robosuite | Meta-World | ManiSkill 3 |
|---|---|---|---|---|---|
| Task 수 | **100 paper / 106 repo HEAD** (`rlbench/tasks/`) | **130** = LIBERO-Spatial 10 + Object 10 + Goal 10 + LIBERO-90 + LIBERO-Long 10 | 9 표준 + 18 MimicGen | **50** (모두 Sawyer) | 12 도메인 (총수 미공표) |
| 표준 sub-suite | **PerAct-18** (18 tasks × 249 variations × 25 demos × 100 eval episodes) | LIBERO-Spatial / -Object / -Goal / -Long; LIBERO-100 (= 90+10) | Lift/Can/Square/Transport/ToolHang (robomimic canonical) | MT1/MT10/MT50/ML1/ML10/ML45 | 미통일 |
| Few-shot 분할 | `FS10_V1`, `FS25_V1`, `FS50_V1`, `FS95_V1` (train+5 test) | 21개 task ordering 으로 lifelong 평가 | (별도) | ML10 (10 train + 5 test), ML45 (45+5) | 미공표 |
| Multi-task 세트 | `MT15`/`MT30`/`MT55`/`MT100` (train only, no test split) | LIBERO-100 (lifelong) | (별도) | MT10, MT50 | 미공표 |
| Variation 축 | color (20 named), position (`SpawnBoundary.sample()`), target identity, base rotation; size/shape/texture 는 명시 X | spatial layout / object identity / goal predicate / long-horizon | 초기 위치 random | task-별 goal 위치 random | task-별 |
| Demos/task | dataset_generator (variable) | **50** | ~200 human (robomimic) | (없음) | "millions of frames" |
| Eval rollouts/task | PerAct: 100 | **20** (default `n_eval=20`) | (논문별 상이) | **50** (Meta-World+) | (task-별) |
| Episode 길이 | 환경 자체 제한 없음; 예제 40 steps; BridgeVLA `--episode-length 25` | **600** steps (=30 s @ 20 Hz) | 500 steps default | task별 fixed | task별 |
| Success metric | per-step binary `task.success()` (sparse reward) | per-episode binary (goal predicate) | per-episode binary + Wiping % coverage | per-episode binary | `success_once` / `success_at_end` |
| Shaped reward | reach_target, take_lid_off_saucepan **2개만** | (no) | (task별) | (task별) | (task별) |
| Multi-seed 표준 | (별도) | (별도) | (별도) | **IQM over 10 seeds** (Meta-World+) | (별도) |
| 일반화 평가 | COLOSSEUM (RLBench 별도 벤치, 20 task × 14 perturbation 축) | LIBERO-PRO (perturbation under VLA) | (없음) | ML10/ML45 (meta-RL holdout) | (없음 표준) |
| Lifelong / continual | 없음 | **있음** — 21 orderings × AUC, FWT, NBT | 없음 | meta-RL ML 세트 (다름) | 없음 |

`[refs: findings/10-source-01-rlbench.md §8; findings/10-source-02-libero.md §8; findings/10-source-03-...md §A.8,§B.8,§C.8]`

**시사점.**
- **RLBench 의 표준 protocol 은 PerAct-18 이다 (paper 자체보다는 downstream 합의).** 본 repo 의 `docker/README.md:L191` 가 `peract18/` 디렉터리를 인용한다. 18 tasks × 25 demos × 100 episodes 가 사실상 표준. `[ref: findings/10-source-01-rlbench.md §6, §8]`
- **LIBERO 의 lifelong protocol 은 유일하다** — 21 task orderings × {AUC, FWT, NBT}. Continual/lifelong RL 베이스라인이 필요하면 LIBERO 거의 유일. `[ref: findings/10-source-02-libero.md §8]`
- **Meta-World 의 ML10/ML45 는 meta-RL holdout 표준** — task-level few-shot 일반화 평가에는 RLBench/LIBERO/Robosuite/ManiSkill 어느 것보다 잘 다듬어져 있다. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.8]`
- **RLBench 의 sparse reward 가 거의 모든 task** (shaped 는 2개) — RL 학습 자체에는 hostile. PerAct/RVT 가 imitation 만으로 학습한 이유의 일부. `[ref: findings/10-source-01-rlbench.md §8]`
- 일반화 평가가 별도로 필요한 경우: RLBench → **COLOSSEUM** (20 tasks × 14 perturbations, BridgeVLA 64.0%), LIBERO → **LIBERO-PRO** (OpenVLA/π0/π0.5 perturbation 분석). `[ref: findings/10-source-01-rlbench.md §6; findings/10-source-04-vla-adoption.md §LIBERO ranking]`

---

## 3. VLA × 벤치마크 채택 매트릭스 (요약)

**§2.6.a 매트릭스 기준의 거시 패턴:**

| 그룹 | 대표 모델 | 주 sim 벤치 | 비고 |
|---|---|---|---|
| **OXE-pretrained generalist VLA** | OpenVLA, OpenVLA-OFT, Magma, RoboFlamingo, π0/π0.5(post-pub), CogACT | **LIBERO** (+ SimplerEnv) | LIBERO 가 표준; CogACT/Magma 는 SimplerEnv 도 |
| **3D-manipulation (voxel/pcd input)** | PerAct, RVT, RVT-2, Act3D, 3D Diffuser Actor, BridgeVLA | **RLBench** (+ CALVIN, COLOSSEUM, GemBench) | 18-task PerAct protocol 이 사실상 표준 |
| **Real-robot only generalist** | RT-1, RT-2 (Language-Table 만), RT-X, π0 (paper), π0.5 (paper), Octo | none / minimal | sim-to-real gap 회피, real eval 중심 |
| **Diffusion Policy 계열** | Diffusion Policy, ScaleDP | **Robomimic** (+ Push-T, BET, Franka Kitchen) | Meta-World/ManiSkill 평가 X (audit 보정) |
| **Humanoid foundation** | GR00T N1 | RoboCasa, DexMG, GR-1 Tabletop | 자체 sim suite 구축 |

`[ref: findings/10-source-04-vla-adoption.md §Summary Table, §LIBERO ranking, §Trends]`

**핵심 인사이트.** RLBench 와 LIBERO 는 **non-overlapping VLA 커뮤니티**에서 dominant 하다. BridgeVLA 처럼 두 진영을 brigding 하려는 시도가 등장하지만 (BridgeVLA 는 RLBench-only), 현재 시점에서 두 진영이 같은 paper 에서 평가되는 일은 드물다. `[ref: findings/10-source-04-vla-adoption.md §Trends 1–2]`

---

## 4. RLBench 가 강한 지점 / 약한 지점

### 4.1 강점

- **5-카메라 multi-modal 관측 (RGB+Depth+PointCloud+Mask × 5 viewpoints)** 이 기본값 — 3D-manipulation 모델에 즉시 적합. `[ref: findings/10-source-01-rlbench.md §3, §4]`
- **NL 어노테이션이 task 정의에 native** — `init_episode(index) -> List[str]` 가 variation 별로 multiple phrasings 를 반환. post-hoc CLIP 라벨링 불필요. `[ref: findings/10-source-01-rlbench.md §4]`
- **3D-manipulation 계열 (PerAct, RVT, RVT-2, 3DDA, BridgeVLA) 의 표준 sim 벤치마크** — PerAct-18 (18 tasks × 249 variations × 100 demos) 가 자리잡았고 BridgeVLA 까지 이어진다. `[ref: findings/10-source-01-rlbench.md §6; findings/10-source-04-vla-adoption.md §G–J, §E]`
- **풍부한 액션 모드** — 6종 (`JointVelocity/Position/Torque`, `EndEffectorPoseViaPlanning/IK`, `ERJointViaIK`) + RRTConnect motion planning 내장. `[ref: findings/10-source-01-rlbench.md §4]`
- **COLOSSEUM 일반화 벤치마크** 가 RLBench 와 호환되는 별도 평가 도구로 존재 — 14 perturbation axes. `[ref: findings/10-source-01-rlbench.md §6]`
- **CoppeliaSim 자체는 5종 물리 엔진** (Bullet/ODE/Vortex/Newton/MuJoCo) 을 지원 — RLBench 가 (선택만 한다면) MuJoCo physics 위에서도 돌 수 있다. 단 default 가 무엇인지는 repo 에 명시되어 있지 않다. `[ref: findings/10-source-01-rlbench.md §1; findings/30-audit-divergences.md §3.d]`

### 4.2 약점

- **CoppeliaSim 4.1.0 Edu 하드 핀 (newer = segfault) + Python 3.8 정확 매칭** — 미래 업그레이드 경로가 없다. `[ref: findings/10-source-01-rlbench.md §1, §7]`
- **headless 가 native 가 아님** — Xvfb / X11 / VirtualGL 중 하나 필요 + `QT_PLUGIN_PATH=$COPPELIASIM_ROOT` 없이는 silent black-frames 버그. `[ref: findings/10-source-01-rlbench.md §3, §7]`
- **렌더링이 CPU/software GLX** — GPU 가 ML inference 외에는 안 쓰인다. `[ref: findings/10-source-01-rlbench.md §3]`
- **GPU-parallel sim 부재** — 1 process per env, vectorization 은 spawn-multiprocess 만 가능. ManiSkill 3 의 30k+ FPS 대비 차이가 크다. `[ref: findings/10-source-01-rlbench.md §3]`
- **GUI 의존 task 저작** — 신규 task 추가 시 CoppeliaSim task builder GUI 필수. cluster CI 에 hostile. `[ref: findings/10-source-01-rlbench.md §2]`
- **데모 포맷이 pickle+PNG** (HDF5 아님) — LeRobot/HuggingFace ecosystem 통합 시 변환 필요. `[ref: findings/10-source-01-rlbench.md §4]`
- **단일 embodiment 위주** — Panda/Jaco/Mico/Sawyer/UR5 의 5종 tabletop arm; humanoid/mobile/quadruped 없음. `[ref: findings/10-source-01-rlbench.md §5]`
- **Grasp 가 "rigid attach hack"** — 진짜 contact-force 시뮬 아님. friction-rich/dexterous task 에는 부적합. `[ref: findings/10-source-01-rlbench.md §5]`
- **sparse reward 가 거의 모든 task** (shaped 2개만) — pure RL 학습에는 어렵다. `[ref: findings/10-source-01-rlbench.md §8]`
- **OXE-pretrained generalist VLA 진영에서 사실상 부재** — OpenVLA/Octo/π0/π0.5/RT-X 모두 RLBench 미평가. `[ref: findings/10-source-04-vla-adoption.md §Trends 2]`
- **lifelong / meta-RL 표준 분할 없음** — Few-shot/Multi-task 분할은 있으나 catastrophic forgetting/forward transfer 측정 protocol 부재. `[ref: findings/10-source-01-rlbench.md §8]`
- **결정성 미보장** — `Demo.restore_state()` 는 `np.random` 만 복원, 물리 상태는 복원 X. `[ref: findings/10-source-01-rlbench.md §1]`

---

## 5. MuJoCo / SAPIEN 진영 각각이 강한 지점

### 5.1 LIBERO

- **BDDL DSL 로 task 가 텍스트 한 줄** — "in principle infinite" task 생성, GUI 없음. `[ref: findings/10-source-02-libero.md §2]`
- **MuJoCo native EGL** — `MUJOCO_EGL_DEVICE_ID=GPU_ID` 한 줄로 headless GPU 렌더, X display 불필요. `[ref: findings/10-source-02-libero.md §3, §7]`
- **HDF5 demo 50/task × 130 tasks** + HuggingFace `yifengzhu-hf/LIBERO-datasets` (24k+ DL/mo) + LeRobot integration. `[ref: findings/10-source-02-libero.md §4, §6]`
- **2024–2025 generalist VLA 의 de facto 표준 sim 벤치** — OpenVLA, OpenVLA-OFT, Magma, RoboFlamingo, MimicPlay, MUTEX, TAIL 등이 사용. `[ref: findings/10-source-02-libero.md §6; findings/10-source-04-vla-adoption.md §LIBERO ranking]`
- **Lifelong learning protocol** 이 유일 — 21 task orderings × AUC/FWT/NBT. `[ref: findings/10-source-02-libero.md §8]`
- **Native NL annotation** (`(:language ...)` in BDDL) — RLBench 와 함께 둘뿐. `[ref: findings/10-source-02-libero.md §4]`
- **LIBERO-PRO** (arXiv:2510.03827, Oct 2025) 가 perturbation 일반화 평가를 제공. `[ref: findings/10-source-04-vla-adoption.md §A; findings/30-audit-consistency.md §1.4 (날짜 보정)]`

### 5.2 Robosuite

- **로봇 다양성 v1.5** — 10 robots (7 tabletop arms + Baxter bimanual + GR1 humanoid 24-DoF + Spot legged + Tiago mobile), 9 grippers (Robotiq3F, Inspire dex hands 포함), 4 bases (fixed/mobile/legged). `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.5]`
- **6 controllers + variable impedance + Whole-body Control (v1.5)** — multi-controller 비교 실험에 최적. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.4, §A.5]`
- **modular Python composer** — `RobotModel + Arena + MujocoObject + Task` 로 procedural scene 생성. GUI 없음, MJCF 직접 편집 옵션도 열림. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.2]`
- **Diffusion Policy / robomimic / MimicGen 파이프라인** — robosuite (collect) → robomimic (process/train) → MimicGen (scale to 50k+ demos) 이 정착된 워크플로. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.6]`
- **MuJoCo EGL native headless** — install 부담 RLBench 대비 매우 낮음 (`pip install robosuite`). `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.7]`
- **Isaac Sim renderer integration (v1.5)** — photorealistic 옵션. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.3]`

### 5.3 Meta-World

- **State-only by default (39-D vector)** — vision 제거로 multi-task RL 의 task-knowledge transfer 만 isolate. 빠르고 reproducible. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.3, §B.4]`
- **MT50 / ML45 의 multi-task / meta-RL 표준** — task-level few-shot 일반화 측정용. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.8]`
- **Meta-World+ (arXiv:2505.11289)** — mujoco-py → `mujoco` 마이그레이션 완료, IQM over 10 seeds 표준화. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.7, §B.8]`
- **간단한 install** — `pip install metaworld`. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.7]`

### 5.4 ManiSkill 3

- **GPU-parallel sim + rendering** — RTX 4090 단일에서 RGBD+Segmentation **30,000+ FPS**, PickCube 128 envs ≈ 3.5 GB GPU (Isaac Lab 14.1 GB 대비 1/4). `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.3]`
- **20+ robots** — Panda/UR5e/Xarm7/Sawyer/Jaco (tabletop), Fetch/Stretch (mobile), AnyMAL-C (quadruped), Unitree H1/G1 (humanoid), dexterous hands, floating gripper. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.5]`
- **URDF + MJCF asset loading** — 2000+ models (YCB, ShapeNet, PartNet-Mobility) 가 MS2 시점부터 통합. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.2]`
- **PyTorch Kinematics 기반 GPU-parallel IK controllers**. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.4]`
- **공식 Docker** `maniskill/base` Docker Hub. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.7]`
- **HDF5 demo + millions of frames** (motion planning, RL, Meta Quest 3 teleop) + RFCL/RLPD 통합. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.4]`
- **TD-MPC2, Octo, RDT-1B, RT-X 의 baseline implementations** ship 됨 (단 baseline ≠ paper-reported eval — audit D22 참조). `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.6; findings/30-audit-divergences.md D22]`
- **SimplerEnv** 가 MS2 기반 — CogACT/Magma 가 채택하는 real-to-sim bridge. `[ref: findings/10-source-04-vla-adoption.md §K]`

---

## 6. 사용자 상황별 권장 사항

### 6.1 BridgeVLA 처럼 3D 매니퓰레이션 + RLBench 생태계 안에서 작업 중이라면

**유지 + 보강.** RLBench (PerAct-18 protocol, 5-camera multi-modal obs, native NL, COLOSSEUM 일반화 평가) 가 이 sub-field 의 표준이고 BridgeVLA paper §4.1 의 88.2% (RLBench), 64.0% (COLOSSEUM), 50.0% (GemBench) 가 모두 RLBench 계열이다. 본 repo 의 standalone Docker (`docker/Dockerfile`, `docker/bridgevla.Dockerfile`) 와 `QT_PLUGIN_PATH` fix 가 운영 부담을 해결해준다. `[ref: findings/10-source-04-vla-adoption.md §E; findings/10-source-01-rlbench.md §7]`

### 6.2 OpenVLA fine-tune / 일반 VLA 비교 실험을 추가하려면

**LIBERO 를 추가하라.** OpenVLA paper Appendix E 가 LIBERO-Spatial/Object/Goal/Long 의 4개 suite × 500 rollouts 를 보고하고 (3 seeds × 500), OpenVLA-OFT 가 97.1% 까지 끌어올림. Magma, π0/π0.5 post-pub checkpoint, RoboFlamingo, MimicPlay, MUTEX, TAIL 도 모두 LIBERO 사용. 본 user 가 BridgeVLA 를 RLBench 에서 돌리는 동시에 LIBERO 까지 추가하면 — 두 진영을 모두 cover 하는 매우 드문 paper 가 된다 (현재 BridgeVLA 는 RLBench-only). `[ref: findings/10-source-04-vla-adoption.md §A; findings/10-source-02-libero.md §6]`

### 6.3 대규모 RL 트레이닝, 1 GPU 에 10k env 가 필요하면

**ManiSkill 3.** 단일 RTX 4090 에서 RGBD 30k+ FPS, PickCube state-based training ~1분 (MS2 CPU 대비 15× 가속). PhysX GPU sim + Vulkan parallel rendering 의 조합은 현재 LIBERO/Robosuite/Meta-World/RLBench 어디서도 매칭 불가. Single-task 1-GPU RL 베이스라인을 5분 안에 돌리고 싶으면 ManiSkill 3 가 유일. 단점은 (a) 상업 사용 시 PhysX 라이선스, (b) Vulkan WSL 미지원, (c) VLA paper 진영에서는 거의 미사용 — 즉 RL 실험 위주일 때만 권장. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.3, §C.6, §C.7]`

### 6.4 멀티 로봇 / 멀티 컨트롤러 비교가 필요하면

**Robosuite v1.5.** 10 robots × 9 grippers × 4 bases × 6 controllers + WBC + variable impedance. Bimanual (Baxter), humanoid (GR1 24-DoF), mobile (Tiago/Omron), legged (Spot) 까지 한 framework 에서 다룬다. RLBench (5 arms tabletop only) 나 LIBERO (Panda only), Meta-World (Sawyer only) 가 절대 매칭 못 함. ManiSkill 3 가 robot 다양성에서는 능가하지만 controller 의 variable-impedance/WBC 깊이는 Robosuite 가 앞선다. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.4, §A.5]`

### 6.5 메타-RL / lifelong learning 베이스라인이 필요하면

- **Meta-RL (task-level few-shot 일반화):** **Meta-World** ML10/ML45 + Meta-World+ IQM-over-10-seeds 표준. RLBench 의 FS10/25/50/95 도 비슷한 의도지만 표준 protocol 정립 X. `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.8]`
- **Continual / lifelong IL:** **LIBERO** — 21 task orderings × AUC/FWT/NBT 평가, ER/EWC/PackNet/Multitask 베이스라인 동봉. RLBench 에는 이런 protocol 부재. `[ref: findings/10-source-02-libero.md §8]`

---

## 7. 확인되지 않은 사항 / 불확실성

| # | 사항 | 출처 / 비고 |
|---|---|---|
| U1 | RLBench `.ttt` 안에 embedded 된 default physics engine (Bullet/ODE/Vortex/Newton/MuJoCo 중) — Python source 에 명시 X | `[ref: findings/10-source-01-rlbench.md §1; findings/30-audit-divergences.md §3.d]` |
| U2 | RLBench `rlbench/task_ttms/` 정확한 `.ttm` 파일 개수 — source-01 §2 는 "106 files", §8 은 "108 entries (107 non-init)" 로 내부 불일치 | `[ref: findings/30-audit-divergences.md D2]` |
| U3 | RLBench / Robosuite / Meta-World / LIBERO 의 measured FPS — 어느 공식 docs 도 표준 hardware 기준 FPS 미보고 (ManiSkill 3 만 RTX 4090 RGBD 30k+ FPS 공표) | `[ref: findings/30-audit-completeness.md §2 items 2–3]` |
| U4 | RLBench 의 cross-platform bitwise determinism — CoppeliaSim docs 는 Newton "deterministic solver" 외에는 비보장 | `[ref: findings/10-source-01-rlbench.md §1]` |
| U5 | Hiveformer arXiv ID 및 ARP (Autoregressive Policy) arXiv ID — source-01 §6 에서 "unconfirmed" 로 flag | `[ref: findings/10-source-01-rlbench.md §6]` |
| U6 | Robosuite measured sim FPS / 공식 Docker 부재 — source-03 web-only extraction 의 한계 | `[ref: findings/30-audit-completeness.md §2 item 1, 3]` |
| U7 | Meta-World 의 image-mode rendering 해상도 / multi-camera 옵션 — 공식 docs 미문서화 | `[ref: findings/30-audit-completeness.md §2 item 6]` |
| U8 | ManiSkill 3 의 정확한 task 수 — paper 는 "12 domains" 만 enumerate, 개별 task 합계는 "not precisely enumerated", beta 카테고리 존재 | `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §C.8]` |
| U9 | vla-eval unified harness 의 arXiv ID — source-04 가 인용한 `arXiv:2603.13966` 은 미래 ID (2026.03) 로 보여 typo 의심 | `[ref: findings/30-audit-consistency.md §1.4 item 2]` |
| U10 | π0 / π0.5 의 LIBERO post-publication checkpoint 공식 평가 수치 — paper 에는 없고 openpi GitHub 에만 존재 | `[ref: findings/10-source-04-vla-adoption.md §C]` |
| U11 | GR00T N1 의 LIBERO eval — GitHub issue (#136, #191) 에는 언급, 공식 whitepaper 에는 부재 | `[ref: findings/10-source-04-vla-adoption.md §F]` |
| U12 | LIBERO 의 contact-model 세부 (timestep, integrator, solver) — friction tuple 외에는 미공개 | `[ref: findings/30-audit-completeness.md §2 item 5]` |
| U13 | source-03 의 ecosystem 주장 4건 (OpenVLA→robosuite, Octo→robosuite/ManiSkill, Diffusion Policy→Meta-World/ManiSkill) 는 audit 에서 hallucination 으로 판정 — source-04 의 paper-grounded 매트릭스만 신뢰함 | `[ref: findings/30-audit-divergences.md D4, D16, D22; findings/30-audit-consistency.md §1.3]` |

---

## 8. 참고 파일 인덱스

- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/_progress.md` — source × fact matrix
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/10-source-01-rlbench.md` — RLBench (repo+paper)
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/10-source-02-libero.md` — LIBERO (repo+paper)
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/10-source-03-robosuite-metaworld-maniskill.md` — Robosuite + Meta-World + ManiSkill (web-only; audit-flagged)
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/10-source-04-vla-adoption.md` — VLA paper × benchmark adoption 매트릭스 (paper-grounded, audit 권위)
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/30-audit-divergences.md` — 25개 claim-pair 충돌 + 판정 (D4/D13/D16/D22 가 source-03 보정)
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/30-audit-consistency.md` — suspicious extraction 목록 + overall MEDIUM 판정
- `/home/theo_lab/RLBench_docker/research/rlbench_vs_mujoco/findings/30-audit-completeness.md` — lens × source coverage 매트릭스 + Phase F shortlist

---

*Generated 2026-05-21. 본 survey 의 모든 사실 주장은 위 findings 파일 라인을 따라가면 underlying paper/repo line 까지 추적된다. audit 판정과 source 가 충돌할 경우 audit 을 우선했다.*
