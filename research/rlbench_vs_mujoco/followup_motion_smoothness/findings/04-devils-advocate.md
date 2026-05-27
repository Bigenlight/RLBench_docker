# Devil's Advocate — RLBench 끊김 원인의 대안 가설 점검

**Date:** 2026-05-21
**Stress-tests:** `findings/01-rlbench-demo-pipeline.md`, `findings/02-model-action-spaces.md`, `findings/03-synthesis.md`
**Role:** 선행 두 agent의 결론(action space + scripted-demo가 주원인)에 대한 반대 심문 — 누락된 confounder, 과대평가된 인과를 찾는다.

---

## 0. 선행 결론 요약 (steelman 대상)

- 주원인: keypose action space + planner-mediated blocking 실행 (`MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())`)
- 보조요인: scripted-waypoint demo 데이터 (각 waypoint = 정지 pose)

코드 흐름(`action_mode.py:37-42`, `arm_action_modes.py:273-280`)과 논문 인용에 직접 매핑된 견고한 결론이다. 다만 **시각적 끊김이 정확히 어디서 오는가** — (i) planning pause, (ii) gripper actuation pause, (iii) keypose 도착 후 정지, (iv) inference latency — 의 메커니즘에 따라 ranking이 달라진다.

---

## 1. 대안 가설 8가지 — 증거와 평가

### H1. Inference latency가 보이는 정지를 만든다

**가설:** BridgeVLA 한 step 추론이 ~0.21 s (RTX 4090) — `findings/02 §1.1`. 추론 중 CoppeliaSim은 idle, 그래서 영상에 "멈춤"이 보일 것이다.

**증거:**
- `YARR/yarr/utils/rollout_generator.py:46-67` — `for step in range(episode_length): act_result = agent.act(...); transition = env.step(act_result)` 구조. `agent.act()` 동안 `scene.step()`을 호출하는 코드가 없음.
- **결정적 반증:** 비디오 프레임은 `Scene._step_callback`을 통해 `scene.step()` 호출마다 1장씩 캡처된다 (`peract/helpers/custom_rlbench_env.py:95, 117-121`, `scene.py:314-318`). 즉 **추론 중에는 `scene.step()`이 안 불리고 callback도 안 불리고 프레임도 캡처되지 않는다.** mp4 안에 inference-pause는 **존재하지 않는다** (skip된다).
- 확인: `ffprobe`로 `bridgevla_close_jar_success.mp4` = 4.72 s @ 25 fps = 118 프레임. sim @ 20 Hz × 1 frame/step → 118 step = 5.9 s 시뮬레이션 시간. 추론 1회 0.21 s × ~6 keyposes ≈ 1.3 s가 통째로 빠진 것과 일관됨.

**Severity:** **제거됨.** 실시간 viewer로 본다면 보이지만, **저장된 mp4에서는 invisible**. 사용자가 보고 있는 끊김의 원인이 아니다.

---

### H2. 영상 frame rate / playback artifact

**가설:** RLBench eval 영상이 매 K번째 sim step만 캡처해서 jerky하게 보일 수 있다.

**증거:** `_my_callback`(`custom_rlbench_env.py:117-121`)은 매 `scene.step()`마다 1프레임 → K=1, 다운샘플 없음. `record_fps = 25` (`eval.py:322`) vs 캡처 20 Hz → 1.25× 가속, stair-step 효과 없음.

**Severity:** **거의 제거.** 재생만 빨라짐, segmentation 자체와 무관.

---

### H3. CoppeliaSim 50 ms timestep이 stair-step 모션을 만든다

**가설:** sim step 50 ms (20 Hz) vs MuJoCo/LIBERO 2 ms timestep → 큰 step이 계단형 모션을 만들 수 있다.

**증거:** `task_environment.py:18` `_DT = 0.05`. 그러나 path execution은 dense joint config sequence를 매 50ms 한 config씩 진행 (`arm_action_modes.py:274-276`) → path 안에 이미 보간이 있어 arm motion 자체는 부드러움. 사용자가 본 끊김은 매크로(keypose) 단위 정지, timestep 무관.

**Severity:** **미시적, 주원인 아님.**

---

### H4. Gripper-state phase 자체가 시각적으로 distinct하다

**가설:** `MoveArmThenGripper`는 arm 다음에 gripper를 순차 실행. gripper actuation 동안 arm은 정지(gripper만 닫힘/열림). 사용자가 보는 "정지"는 keypose 사이 pause가 아니라 *gripper phase 동안 arm hold*일 수 있다.

**증거 — 강력함:**
- `gripper_action_modes.py:52-57` — `Discrete._actuate()`는 `scene.pyrep.step()` + `scene.task.step()`을 직접 호출. **`scene.step()`을 호출하지 않음** → step_callback이 trigger되지 않음 → **gripper actuation 동안 비디오 프레임이 캡처되지 않음.**
- `gripper_action_modes.py:82-86` — gripper open 후 추가 10 step `pyrep.step() + task.step()` (object drop용). 역시 callback 미호출.
- **함의:** mp4에서 gripper phase는 **frame이 아예 없어 점프 컷**으로 나타난다 — arm position은 변하지 않으므로 "정지처럼" 보이지만 정확히는 "한 frame에서 arm은 그대로, gripper만 갑자기 닫힘/열림" 같은 컷.
- 그런데 잠깐 — `Scene.step()`(callback 포함)이 호출되는 곳은 arm path execution과 `get_demo()` 내부의 demo 생성 루프뿐. eval에서 gripper는 callback 우회한다.

**선행 결론과의 비교:** `findings/01 §6`은 "gripper actuation도 blocking" + "extra 10 steps for object drop"이라고 명시했고 `findings/01 §1`은 demo 생성에서 `record_gripper_closing=False` 기본값이라 gripper 프레임이 dropped된다고 적시. **eval video에서도 같은 패턴(callback 우회로 인한 컷)이 일어남을 추가로 발견.**

**Severity:** **유의미한 보조 원인.** 끊김의 일부는 gripper actuation의 시각적 점프 컷이며, 선행 결론이 "blocking gripper로 정지"라고 한 묘사보다 더 강한 시각 효과("frame skip = 점프 컷")를 만든다. 다만 모든 keypose 사이 정지를 설명하지는 않음 (gripper open/close가 없는 keypose 전환도 끊김이 있음).

---

### H5. 카메라/영상 편집 artifact

**가설:** project page 영상이 chained/cropped clip일 수 있다.

**증거:** `eval.py:317-368` — 단일 episode의 `_recorded_images` array를 그대로 mp4로 인코딩, chaining 없음. 유일한 "편집"은 `_append_final_frame` (`custom_rlbench_env.py:123-130`)의 success=green/fail=red 10 색 프레임, 그리고 `record_end`(rollout_generator.py:107)의 `steps=60` hold (3초 @ 20Hz).

**Severity:** **영상 *끝* 정지에만 기여, 중간 keypose 사이 끊김과 무관.**

---

### H6. "정지"는 RRTConnect planner의 계산 시간일 수 있다

**가설:** path 계산이 오래 걸려 정지처럼 보일 수 있다.

**증거:**
- `arm_action_modes.py:182-183` docstring: "**path planning can be slow, often taking a few seconds in the worst case**" — 코드 작성자 본인이 인정.
- `arm_action_modes.py:255-266` — `get_path(..., trials=100, max_time_ms=10, ...)`. 최악 ≈ 1 s.
- **결정적:** `get_path()`는 `path.step()` 전에 끝나 그 동안 `scene.step()` 미호출 → callback 미호출 → 프레임 미캡처. **mp4에는 invisible** (H1과 동일 원리). live viewer로 본다면 visible.

**Severity:** **mp4에서는 invisible, live 관찰에서는 큰 기여.** 사용자가 본 매체에 따라 평가가 달라짐.

---

### H7. Reward / success check pause

**가설:** waypoint 사이에 success condition 평가용 pause.

**증거 (제거):** `arm_action_modes.py:277-280`, `scene.py:373-376` 모두 path step 루프 *안*에서 평가. `scene.task.success()`는 Python 호출 < 1 ms.

**Severity:** **제거.**

---

### H8. Network / file IO pause

**가설:** disk logging이 sim을 멈출 수 있다.

**증거 (제거):** `_my_callback`은 RGB을 메모리 list에 append만, mp4 인코딩은 episode 종료 후 batch (`eval.py:317-368`). 동기 file write 없음.

**Severity:** **제거.**

---

## 2. 새로 발견된 9번째 가설 — 영상 captures가 step_callback에만 의존하는 비대칭성

**가설 (devil's-advocate 발굴):** `scene.step()`은 callback을 부르고 `pyrep.step() + task.step()`은 부르지 않는다는 비대칭이 시각 효과를 만든다.

- arm planning 실행 루프: `scene.step()` → 프레임 캡처 O.
- gripper actuation 루프 (`gripper_action_modes.py:54-57`): `pyrep.step() + task.step()` → 프레임 캡처 X.
- gripper open 후 object drop 10 step (`gripper_action_modes.py:83-86`): 동일하게 캡처 X.
- 데모 생성의 default `record_gripper_closing=False` (`observation_config.py:54`)와 **별개로**, eval video에서도 gripper actuation 동안 프레임이 사라진다.

이 비대칭이 만드는 효과: 영상에서 **arm은 부드럽게 움직이다가 keypose 도착 → 그 frame 다음에 gripper가 이미 닫힌(또는 열린) state로 점프 컷 → 다시 부드럽게 움직이다 keypose → 점프 컷**. 사용자가 보는 "segmented" 느낌의 **상당 부분이 이 점프 컷**일 가능성이 높다.

**Severity:** **유의미한 1차 기여.** 선행 결론은 "blocking gripper로 정지"라고 묘사했으나 실제로는 더 강한 시각 효과(컷)가 일어남. 단, 모든 keypose 사이 정지를 설명하지는 않음.

---

## 3. 최종 ranking

### 가장 강력하게 확정된 주원인 (영상 mp4 관점)

1. **Keypose action space + planner-mediated blocking arm execution** — `MoveArmThenGripper(EndEffectorPoseViaPlanning(), Discrete())`. arm은 keypose에 도착할 때까지 부드럽게 움직이고, 도착 시점에 frame이 캡처된 채로 path 루프가 exit. 다음 keypose까지 sim이 멈춰 있고 (frame 미캡처) 다음 path 시작 시 frame이 새로 캡처 시작. **mp4 안에서 보이는 "정지"는 path의 마지막 1–2 frame이 같은 pose에 머무는 것 + 다음 path 첫 frame까지의 점프**. 선행 결론과 일치.

2. **Gripper actuation의 callback 우회 (= 점프 컷)** — `gripper_action_modes.py:54-57`이 `pyrep.step() + task.step()`을 쓰고 `scene.step()`을 안 써서 step_callback이 trigger되지 않음. arm pose는 그대로 freeze된 채 gripper state만 점프. 선행 결론의 "blocking gripper로 정지"를 한 단계 더 정교화한 결과 — 실제로는 *정지*보다 *frame skip*이다.

### 무시하지 않아야 할 대안 (live 관찰 시 추가 기여)

3. **Inference latency 0.21 s** — mp4에서는 invisible, **live viewer/screen recording에서는 visible.** 사용자가 어떤 매체로 봤는지에 따라 ranking이 변동.

4. **RRTConnect planner 계산 시간** — docstring이 "few seconds in worst case"라 인정. mp4에서는 invisible, live에서는 visible.

### 명확히 제거된 대안

5. **Network/file IO pause (H8)** — sim 루프와 동기적이지 않음. mp4 인코딩은 episode 종료 후 단일 batch.

### 부분적 기여 / 미시적

- **CoppeliaSim 50 ms timestep (H3)** — 매크로 끊김의 원인 아님. path 안에 dense joint config가 있어 path 실행 자체는 부드러움.
- **Playback FPS 1.25–1.5× 가속 (H2)** — 가속만 만들고 끊김은 안 만듦.
- **record_end의 마지막 60 step hold + 10 색 frame (H5)** — 영상 *끝*의 정지에만 기여. 중간 keypose pause와 무관.
- **Reward check (H7)** — 코드상 별도 pause 없음.

---

## 4. 선행 agent 결론의 약점

### 4-1. 시각 효과 메커니즘 미분해

선행 결론은 "blocking으로 정지"로 통합했지만 실제 mp4에서는 (i) arm path 마지막 1-2 frame의 짧은 *정지* + (ii) gripper actuation 동안의 *frame skip 컷* + (iii) inference/planner pause의 *frame skip 컷*이 섞임. frame-by-frame 분석해야 비율 측정 가능.

### 4-2. mp4 vs live 구분 부재

mp4에서는 inference/planner pause가 invisible. 사용자가 본 매체에 따라 원인 가중치가 크게 달라지지만 선행 결론은 이를 구분하지 않았다.

### 4-3. Demo data "강화 요인" 주장의 실증 부재

`findings/03 §3` 마지막 단락의 "scripted demo로 학습된 dense policy도 jerky했을 것"은 실험 없이 thought experiment로만 진행. 명시되지 않은 채 결론에 포함됨.

### 4-4. `Discrete` gripper의 frame skip 효과 누락

선행은 데모 `record_gripper_closing=False`만 짚었으나, **eval video에서도 같은 callback 우회로 gripper actuation이 frame skip 컷으로 나타남** (본 보고서 H4/9 발견).

---

## 5. 정량 가능한 후속 검증 (제안)

1. `bridgevla_close_jar_success.mp4`를 PNG frame으로 분해 → SSIM diff로 "정지 구간"(연속 frame 거의 동일) vs "점프 컷"(frame n→n+1 큰 변화) 비율 측정.
2. `MoveArmThenGripper(JointPosition(), Discrete())`로 강제 실행 → 끊김 패턴 비교. action space가 주원인이면 사라져야 함.
3. `_my_callback`을 gripper actuation 루프에 추가 hook → gripper phase가 frozen vs 점프 컷인지 검증.
4. Live screen capture vs saved mp4 비교 → inference/planner pause가 사용자가 본 영상에 포함됐는지 결정.
