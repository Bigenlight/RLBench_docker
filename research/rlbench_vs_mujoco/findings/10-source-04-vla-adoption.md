# VLA Model Benchmark Adoption: Sim Evaluation Survey

**Purpose:** Identify which simulation benchmarks 2023–2025 VLA and large-scale imitation-learning models actually report numbers on, to inform the RLBench-vs-MuJoCo comparison.

**Date compiled:** 2026-05-21

---

## A. OpenVLA (Kim et al. 2024, arXiv:2406.09246)

### sim_benchmarks_evaluated
**LIBERO only** — specifically four suites: LIBERO-Spatial, LIBERO-Object, LIBERO-Goal, LIBERO-Long (LIBERO-10). Evaluation appears in *Appendix E: LIBERO Simulation Experiments* of the paper.
> "See Appendix E for fine-tuning experiments in simulation." [arXiv:2406.09246 Appendix E]
> "each success rate is the average over 3 random seeds × 500 rollouts each (10 tasks × 50 rollouts per task)" [https://arxiv.org/html/2406.09246v3 Appendix E]

Fine-tuned OpenVLA achieves **76.5%** average success across four LIBERO suites; the follow-on OpenVLA-OFT recipe raises this to **97.1%** [arXiv:2502.19645 §4].

RLBench, Robosuite, Meta-World, ManiSkill: **not evaluated**.

### real_robot_used
Yes — **WidowX** (BridgeData V2 tasks), **Google Robot** (RT-series tasks), **Franka Emika Panda** (Franka-Tabletop and Franka-DROID configurations).
> "We evaluate OpenVLA's ability to control multiple robot platforms 'out-of-the-box' across two setups: the WidowX setup from Bridge V2 and the Google Robot from the RT-series of papers." [arXiv:2406.09246 §5.1]

### training_data
Open X-Embodiment dataset — **970k real-world robot episodes**.
> "OpenVLA, a 7B-parameter open-source VLA trained on a diverse collection of 970k real-world robot demonstrations" [arXiv:2406.09246 abstract]

### emphasis
**Real-robot primary**, with LIBERO simulation as secondary fine-tuning validation.

---

## B. RT-1 / RT-2 / RT-X (Google DeepMind)

### RT-1 (arXiv:2212.06817)

**sim_benchmarks_evaluated:** None as a primary evaluation benchmark. Simulation was used *only* for model selection (not as a reported benchmark).
> "all of our training data comes from the real world (except the experiment in Section 6.3), and the simulator is used only for model selection." [arXiv:2212.06817 Appendix C.3]

**real_robot_used:** Everyday Robots 7-DoF mobile manipulators — fleet of **13 robots** in office kitchen environments.

**training_data:** 130k real-world episodes across 700+ tasks, collected over 17 months. Also includes QT-Opt Kuka data (209k episodes) in cross-robot experiment.

**emphasis:** **Real-robot only.**

---

### RT-2 (arXiv:2307.15818)

**sim_benchmarks_evaluated:** **Language-Table** simulation (Lynch et al. 2022) only.
> "To provide an additional point of comparison using open-source baselines and environments, we leverage the open-source Language-Table simulation environment from Lynch et al. (2022)." [arXiv:2307.15818 §5]
RT-2 achieves **90%** on Language-Table simulation vs. 77% prior SoTA.

RLBench, LIBERO, Robosuite: **not evaluated**.

**real_robot_used:** Yes — **Google 7-DoF mobile manipulator** (same platform as RT-1), ~6,000 evaluation trajectories in office kitchen.

**training_data:** RT-2 co-fine-tunes PaLM-E / PaLI on RT-1 robot trajectory data plus web vision-language data. Training trajectories from 13 robots over 17 months.

**emphasis:** **Real-robot primary**, Language-Table sim used as secondary sanity check.

---

### RT-X / Open X-Embodiment (arXiv:2310.08864)

**sim_benchmarks_evaluated:** None — focused exclusively on real-robot cross-embodiment evaluation.
> "We evaluate the performance of the RT-X model on various robot embodiments" comparing against per-robot baselines. [arXiv:2310.08864 §5]

**real_robot_used:** Yes — **6+ embodiments** including WidowX (Stanford IRIS / UC Berkeley), Google Robot, UR5, xArm, Jaco.

**training_data:** OXE dataset — "9 manipulators...from RT-1, QT-Opt, Bridge, Task Agnostic Robot Play, Jaco Play, Cable Routing, RoboTurk, NYU VINN, Austin VIOLA, Berkeley Autolab UR5, TOTO and Language Table datasets." [arXiv:2310.08864 §3]

**emphasis:** **Real-robot cross-embodiment** — no sim benchmarks.

---

## C. π0 / π0.5 (Physical Intelligence)

### π0 (arXiv:2410.24164)

**sim_benchmarks_evaluated:** **None.** All experiments conducted on real robots.
> "We evaluate our approach by pre-training on over 10,000 hours of robot data, and fine-tuning to a variety of dexterous tasks." [arXiv:2410.24164 §4]
> No mention of RLBench, LIBERO, Robosuite, Meta-World, or ManiSkill. [https://www.pi.website/blog/pi0]

*Note:* π0 checkpoints fine-tuned for LIBERO have been released post-publication (openpi GitHub), but the **original paper reports no sim benchmark numbers**.

**real_robot_used:** Yes — UR5e (single-arm), bimanual UR5e, Franka, bimanual Trossen, bimanual ARX, mobile Trossen, mobile Fibocom. Evaluated on laundry folding, table bussing, box assembly. [arXiv:2410.24164 §4]

**training_data:** "903M timesteps from proprietary π datasets (68 tasks, 8 robots) + 9.1% from open-source data (OXE, Bridge v2, DROID)." [arXiv:2410.24164 §3]

**emphasis:** **Real-robot only** in the original paper.

---

### π0.5 (arXiv:2504.16054)

**sim_benchmarks_evaluated:** **None.** Evaluated exclusively in real-home settings.
> "all of our experiments in novel environments that were not seen in training." [arXiv:2504.16054]
Evaluation: mock home environments and **three real homes** never seen in training.

**real_robot_used:** Yes — bimanual mobile manipulators (two 6-DoF arms, parallel jaw grippers, wheeled holonomic base).

**training_data:** Multi-robot proprietary dataset + open-source data mixture (OXE, Bridge v2, DROID).

**emphasis:** **Real-robot only.**

---

## D. Octo (arXiv:2405.12213)

**sim_benchmarks_evaluated:** **None** — the paper focuses entirely on real-robot experiments.
> "We evaluate Octo on 9 real robot setups across 4 institutions." [arXiv:2405.12213 §4]
No mention of RLBench, LIBERO, Robosuite, Meta-World, or CALVIN. [https://octo-models.github.io/]

**real_robot_used:** Yes — **9 platforms** across 4 institutions: WidowX (Bridge V2), UR5 (Berkeley AutoLab), RT-1 Robot (Google DeepMind), Franka (CMU, Stanford), bimanual Berkeley setups.

**training_data:** Open X-Embodiment dataset — **800k trajectories** from 25 curated datasets. Key contributors: Fractal (17%), Kuka (17%), Bridge (17%), BC-Z (9.1%), Language Table (5.9%). [arXiv:2405.12213 §3]

**emphasis:** **Real-robot only** — sim evaluation absent.

---

## E. BridgeVLA (arXiv:2506.07961, NeurIPS 2025)

**sim_benchmarks_evaluated:** **RLBench, COLOSSEUM, GemBench** — all three are RLBench-derived or use CoppeliaSim/similar.

- **RLBench**: "we perform experiments on 18 tasks from RLBench" with "100 expert demonstrations" per task; "25 trials per task." Achieves **88.2%** average success rate (up from 81.4% SOTA). [arXiv:2506.07961 §4.1]
- **COLOSSEUM**: "20 basic tasks and 12 types of perturbations" including "changes in object texture, color, and size, backgrounds, lighting, distractors and camera poses." Achieves **64.0%** (up from 56.7%). [arXiv:2506.07961 §4.2]
- **GemBench**: "16 tasks (31 variations)" in training; "44 tasks (92 variations)" in testing across four difficulty levels (L1–L4). Achieves **50.0%** average success rate. [arXiv:2506.07961 §4.3]

LIBERO, Robosuite, Meta-World, ManiSkill: **not evaluated**.

**real_robot_used:** Yes — **Franka Research 3** with parallel-jaw gripper and ZED 2i depth camera. 13 tasks, 10 demos each. Achieves **96.9%** basic success and **96.8%** on 10+ tasks with only 3 trajectories/task. [arXiv:2506.07961 §5]

**training_data:** Pre-trained on "120K object detection split of RoboPoint" for 2D heatmap prediction. Fine-tuned on RLBench/COLOSSEUM/GemBench demos. [arXiv:2506.07961 §3]

**emphasis:** **Sim-primary (RLBench ecosystem)** — this is one of the few 2024–2025 VLA papers where RLBench is the primary evaluation.

---

## F. GR00T / GR00T N1 (NVIDIA, arXiv:2503.14734)

**sim_benchmarks_evaluated:** **RoboCasa**, **DexMimicGen (DexMG)**, and **GR-1 Tabletop Tasks (Digital Cousin)**. No RLBench or LIBERO.

- **RoboCasa Kitchen**: "24 tasks" covering "pick-and-place, door opening and closing, pressing buttons, turning faucets." [arXiv:2503.14734 §4]
- **DexMimicGen (DexMG)**: "9 tasks" of "bimanual dexterous manipulation requiring precise two-arm coordination." [arXiv:2503.14734 §4]
- **GR-1 Tabletop Tasks**: "24 tasks" as a "digital counterpart to real-world humanoid datasets" using the GR-1 humanoid. [arXiv:2503.14734 §4]

*Note:* The GitHub issue tracker shows community members fine-tuning GR00T N1 on LIBERO (GitHub NVIDIA/Isaac-GR00T issues #136, #191), but the **official whitepaper does not report LIBERO numbers**.

**real_robot_used:** Yes — **Fourier GR-1 humanoid** and 1X Neo humanoid. [arXiv:2503.14734 §5]

**training_data:** Pyramid-structured: (1) internet-scale web data + human videos (Ego4D, Ego-Exo4D, EPIC-KITCHENS); (2) >750k synthetic trajectories from NVIDIA Omniverse (generated in 11 hours); (3) 88 hours GR-1 teleoperation real data. [arXiv:2503.14734 §3]

**emphasis:** **Humanoid/real-robot** — sim benchmarks are custom humanoid manipulation suites, not standard tabletop benchmarks.

---

## G. PerAct (Shridhar et al., arXiv:2209.05451)

**sim_benchmarks_evaluated:** **RLBench exclusively**.
> "We train and evaluate on 18 RLBench tasks." [arXiv:2209.05451 §4]
> "We train a single multi-task Transformer for 18 RLBench tasks (with 249 variations) and 7 real-world tasks (with 18 variations) from just a few demonstrations per task." [arXiv:2209.05451 §4]

Tasks include: open drawer, slide block, sweep to dustpan, meat off grill, turn tap, put in drawer, close jar, drag stick, stack blocks, screw bulb, put in safe, place wine, put in cupboard, sort shape, push buttons, insert peg, stack cups, place cups.

CALVIN, LIBERO, Robosuite, Meta-World: **not mentioned**.

**real_robot_used:** Yes — **Franka Emika Panda** for 7 real-world tasks (18 variations, 53 total demos). [arXiv:2209.05451 §5]

**training_data:** RLBench expert demonstrations (10–100 demos/task). Real-world: 53 demos total across 7 tasks.

**emphasis:** **RLBench-primary** — this is the canonical 3D-manipulation-on-RLBench paper.

---

## H. RVT / RVT-2 (Goyal et al.)

### RVT (arXiv:2306.14896)

**sim_benchmarks_evaluated:** **RLBench exclusively**.
> "a single RVT model works well across 18 RLBench tasks with 249 task variations." [https://robotic-view-transformer.github.io/]
> "We trained a single RVT model from real world data and a single RVT model from RLBench simulation data." [https://robotic-view-transformer.github.io/]

Achieves 26% higher relative success than PerAct on RLBench.

**real_robot_used:** Yes — demonstrated on real-world manipulation tasks with "~10 demonstrations per task." Robot hardware not specified on the project page.

**training_data:** RLBench expert demos (same setup as PerAct: 100 demos/task).

**emphasis:** **RLBench-primary**.

---

### RVT-2 (arXiv:2406.08545)

**sim_benchmarks_evaluated:** **RLBench exclusively**.
> "We conduct the experiments on a standard multi-task manipulation benchmark developed in RLBench containing 18 tasks." [arXiv:2406.08545 §4]
> "RVT-2 achieves a new state-of-the-art on multi-task RLBench benchmark, improving the success rate from 65% to 82%." [https://robotic-view-transformer-2.github.io/]

100 demos/task for training, 25 unseen demos for testing.

**real_robot_used:** Yes — **Franka Emika Panda** with parallel jaw gripper and Azure Kinect RGB-D camera. Five tasks from prior RVT plus three new high-precision insertion tasks (16mm peg, 8mm peg, 2-prong plug). [arXiv:2406.08545 §5]

**training_data:** RLBench expert demos; ~10 demos per real-world task.

**emphasis:** **RLBench-primary**.

---

## I. Diffusion Policy (Chi et al., arXiv:2303.04137)

**sim_benchmarks_evaluated:** Four benchmarks — **Robomimic**, **Push-T (IBC)**, **Multimodal Block Pushing (BET)**, **Franka Kitchen**.
> "Diffusion Policy outperforms prior state-of-the-art on 12 tasks across 4 benchmarks with an average success-rate improvement of 46.9%." [arXiv:2303.04137 abstract]

- **Robomimic**: Lift, Can, Square, Tool Hang, Transport — 5 tasks with proficient and mixed-quality human demos. This is the primary sim benchmark.
- **Push-T**: T-shaped block pushing (2D, from IBC benchmark).
- **Multimodal Block Pushing**: from Behavior Transformer (BET).
- **Franka Kitchen**: long-horizon multi-task kitchen benchmark.

RLBench, LIBERO, Meta-World, ManiSkill: **not evaluated**.

**real_robot_used:** Yes — **UR5** (real Push-T), **Franka Panda** (sauce pouring/spreading, mug flipping, bimanual egg beater, mat unrolling, shirt folding). [arXiv:2303.04137 §6]

**training_data:** Per-benchmark expert/human demonstrations (no large-scale robot dataset).

**emphasis:** **Balanced sim + real**. Robomimic is the primary sim benchmark; real robot demos validate transfer.

---

## J. 3D Diffuser Actor (Ke et al., arXiv:2402.10885)

**sim_benchmarks_evaluated:** **RLBench** and **CALVIN**.

- **RLBench** (PerAct setup): "18 manipulation tasks, each task has 2-60 variations… 100 training demonstrations per task." Also GNFactor setup: "10 manipulation tasks, 20 training demos per task, single RGB-D camera." Achieves **18.1% absolute gain** over prior SOTA (multi-view), **13.1% gain** (single-view). [arXiv:2402.10885 §4]
- **CALVIN** (PyBullet): "trained on the subset of play data on environments A, B and C and evaluated on 1000 unique instruction chains on environment D" (zero-shot unseen-scene generalization). **9% relative improvement** over prior SOTA. [arXiv:2402.10885 §4]

LIBERO, Robosuite, Meta-World: **not evaluated**.

**real_robot_used:** Yes — **Franka Emika** with Azure Kinect RGB-D. "15 demonstrations per task" across 12 real-world tasks. [arXiv:2402.10885 §5]

**training_data:** RLBench expert demos (100/task); CALVIN play data.

**emphasis:** **Sim-primary (RLBench + CALVIN)**.

---

## K. CogACT (Microsoft, arXiv:2411.19650)

**sim_benchmarks_evaluated:** **SimplerEnv (SIMPLER)** — a real-to-sim bridge built on ManiSkill2/SAPIEN.
> "After training, we evaluate our model within the SIMPLER evaluation environment. This simulation platform is designed to bridge the real-to-sim control and visual gap by faithfully replicating real-world conditions." [arXiv:2411.19650 §4]

Two settings: Visual Matching and Variant Aggregation, on Google Robot and WidowX robot tasks.

Exceeds OpenVLA by **>35%** in sim (SIMPLER) and **55%** in real.
RLBench, LIBERO, Robosuite: **not evaluated**.

**real_robot_used:** Yes — **Realman Arm** (7-DoF, 391 demo samples) and **Franka Arm** (400 demo samples). [arXiv:2411.19650 §5]

**training_data:** OXE subset — "same 25 datasets as Octo/OpenVLA, 0.4M trajectories / 22.5M frames." [arXiv:2411.19650 §3]

**emphasis:** **Primarily real-robot**, with SimplerEnv as validation.

---

## K2. Magma (Microsoft, arXiv:2502.13130, CVPR 2025)

**sim_benchmarks_evaluated:** **SimplerEnv** and **LIBERO**.
- **SimplerEnv**: Google Robot tasks (52.3% success) and Bridge/WidowX tasks (35.4%). [arXiv:2502.13130 §4]
- **LIBERO**: "we testify the effectiveness of the finetuned Magma model by comparing it with OpenVLA in three settings" including LIBERO fine-tuning with limited trajectories. [arXiv:2502.13130 §4]

RLBench, Robosuite, Meta-World: **not evaluated**.

**real_robot_used:** Yes — **WidowX 250** arm, 4 tasks with ~50 trajectories each. [arXiv:2502.13130 §4]

**training_data:** 39M multimodal samples: 2.7M UI screenshots, 970k robotic trajectories (OXE), 25M video samples. [arXiv:2502.13130 §3]

**emphasis:** **Multi-domain (UI + robotics)** — sim benchmarks are secondary.

---

## Summary Table: Model × Benchmark

| Model | RLBench | LIBERO | Robosuite/ Robomimic | Meta- World | Mani- Skill | CALVIN | Simpler Env | Real-only sim |
|---|---|---|---|---|---|---|---|---|
| **OpenVLA** | — | ✓ | — | — | — | — | — | — |
| **RT-1** | — | — | — | — | — | — | — | ✓ (custom) |
| **RT-2** | — | — | — | — | — | — | — | ✓ (Language-Table) |
| **RT-X** | — | — | — | — | — | — | — | ✓ (real only) |
| **π0** | — | — | — | — | — | — | — | ✓ (real only) |
| **π0.5** | — | — | — | — | — | — | — | ✓ (real only) |
| **Octo** | — | — | — | — | — | — | — | ✓ (real only) |
| **BridgeVLA** | ✓ | — | — | — | — | — | — | — |
| **GR00T N1** | — | — | — | — | — | — | — | ✓ (RoboCasa/DexMG) |
| **PerAct** | ✓ | — | — | — | — | — | — | — |
| **RVT** | ✓ | — | — | — | — | — | — | — |
| **RVT-2** | ✓ | — | — | — | — | — | — | — |
| **Diffusion Policy** | — | — | ✓ (Robomimic) | — | — | — | — | — |
| **3D Diffuser Actor** | ✓ | — | — | — | — | ✓ | — | — |
| **CogACT** | — | — | — | — | — | — | ✓ | — |
| **Magma** | — | ✓ | — | — | — | — | ✓ | — |

Legend: ✓ = paper reports numbers; — = not evaluated; "real only" = model has real-robot evaluation but no standard sim benchmark from the listed set.

---

## Which Benchmarks Dominate the VLA Literature?

### Ranked List of Most-Used Sim Benchmarks (2024–2025 VLA papers)

**1. LIBERO** — Used by: OpenVLA, OpenVLA-OFT, π0 (post-publication checkpoint), π0.5 (post-pub checkpoint), Magma, and virtually all recent VLA fine-tuning papers. LIBERO-PRO (arXiv:2510.03827) explicitly states:
> "LIBERO has rapidly become the most widely adopted evaluation suite for VLA, serving as the de facto standard for reporting performance." [arXiv:2510.03827]
> "virtually all recent VLA studies report results on LIBERO" [arXiv:2510.03827]
The vla-eval unified harness (arXiv:2603.13966) lists LIBERO as one of three cross-codebase validated benchmarks. Usage in the 2024–2025 "generalist VLA" literature: dominant.

**2. RLBench** — Used by: PerAct, RVT, RVT-2, 3D Diffuser Actor, BridgeVLA. Consistently used by the **3D-input manipulation** subfield (PerAct/RVT lineage), which specifically targets multi-task language-conditioned manipulation from voxel/point-cloud inputs. The PerAct → RVT → RVT-2 → 3D Diffuser Actor → BridgeVLA chain all benchmark exclusively or primarily on RLBench (with 3D Diffuser Actor also adding CALVIN). However, it is essentially **absent** from the generalist VLA (OXE-trained) literature.

**3. SimplerEnv** — Used by: CogACT, Magma, and increasingly adopted as a real-to-sim proxy for evaluating generalist policies. Built on ManiSkill2/SAPIEN, designed to faithfully replicate Google Robot and WidowX setups. Emerging as the bridge between "real-robot VLA" papers and standardized sim evaluation.

**Honorable mention — CALVIN (PyBullet):** Used by 3D Diffuser Actor for zero-shot generalization evaluation. A niche benchmark for long-horizon task-sequence evaluation. Appears as a secondary benchmark in several 3D-manipulation papers.

**Robomimic:** Primary benchmark for Diffusion Policy and Diffusion Policy derivatives. Used when evaluating manipulation from human demonstrations (proficient/mixed quality), but not dominant in the broader VLA space.

### Emerging Trends

1. **LIBERO is the de facto VLA benchmark (2024–2025):** The generalist VLA literature (OXE-pretrained, Transformer-based) has converged on LIBERO as the standard sim evaluation. This is partly due to its structured task suites (Spatial/Object/Goal/Long), clear success metrics, and the fact that OpenVLA (the most influential open-source baseline) published LIBERO results prominently.

2. **RLBench dominates the 3D-manipulation sub-field but is insular:** The PerAct/RVT/BridgeVLA lineage reports exclusively on RLBench, but these papers are largely absent from the cross-embodiment VLA conversation. The two communities (OXE-generalist vs 3D-manipulation) have largely non-overlapping benchmark choices.

3. **The biggest generalist VLA models (π0, Octo, RT-X) do no sim evaluation at all:** Physical Intelligence, Google DeepMind, and the Octo team all chose to skip simulation entirely and evaluate only on real robots. This reflects a belief that sim-to-real gaps make sim numbers less informative for large-scale real-world models.

4. **SimplerEnv is gaining traction as a middle ground:** For models that want reproducible sim numbers without using LIBERO or RLBench, SimplerEnv (real-to-sim with Google Robot / WidowX setups) is being adopted by CogACT, Magma, and others as a more "real-world-grounded" alternative.

5. **GR00T N1 creates its own benchmark ecosystem:** NVIDIA introduced custom sim suites (RoboCasa, DexMG, GR-1 Tabletop) for humanoid evaluation rather than adopting existing benchmarks — confirming that the humanoid sub-field has diverged from tabletop manipulation standards.

6. **Meta-World and ManiSkill are largely absent from VLA papers:** Despite Meta-World being widely used in RL research and ManiSkill being prominent in sim-to-real research, neither appears as a primary benchmark in any of the major 2024–2025 VLA papers surveyed.

---

## Key Sources

- OpenVLA paper: https://arxiv.org/abs/2406.09246
- OpenVLA-OFT: https://arxiv.org/abs/2502.19645
- Octo paper: https://arxiv.org/abs/2405.12213
- BridgeVLA paper: https://arxiv.org/abs/2506.07961
- BridgeVLA GitHub: https://github.com/BridgeVLA/BridgeVLA
- π0 paper: https://arxiv.org/abs/2410.24164
- π0.5 paper: https://arxiv.org/abs/2504.16054
- GR00T N1 paper: https://arxiv.org/abs/2503.14734
- PerAct paper: https://arxiv.org/abs/2209.05451 / https://peract.github.io/
- RVT paper: https://robotic-view-transformer.github.io/
- RVT-2 paper: https://arxiv.org/abs/2406.08545 / https://robotic-view-transformer-2.github.io/
- 3D Diffuser Actor: https://arxiv.org/abs/2402.10885 / https://3d-diffuser-actor.github.io/
- Diffusion Policy: https://arxiv.org/abs/2303.04137 / https://diffusion-policy.cs.columbia.edu/
- CogACT: https://arxiv.org/abs/2411.19650
- Magma: https://arxiv.org/abs/2502.13130
- RT-2: https://arxiv.org/abs/2307.15818
- RT-X: https://arxiv.org/abs/2310.08864
- LIBERO-PRO (benchmark dominance analysis): https://arxiv.org/abs/2510.03827
- vla-eval unified harness: https://arxiv.org/abs/2603.13966
- SimplerEnv: https://github.com/simpler-env/SimplerEnv

---

## ≤250-Word Summary

**(a) Most-used sim benchmark in 2024–2025 VLA papers:** **LIBERO** is the de facto standard for the generalist VLA literature. LIBERO-PRO (arXiv:2510.03827) confirms "virtually all recent VLA studies report results on LIBERO," and vla-eval lists it as one of only three cross-codebase validated benchmarks. OpenVLA, Magma, and essentially every OXE-pretrained model that reports sim numbers uses LIBERO.

**(b) Most surprising finding:** The largest and most influential generalist VLA models — **π0, π0.5, Octo, RT-1, RT-X** — report **zero simulation benchmark numbers** in their papers. Physical Intelligence and Google DeepMind treat real-robot evaluation as the only valid metric, making simulation results essentially absent from the highest-impact VLA papers of 2024–2025. Yet downstream users and fine-tuning papers use LIBERO as the evaluation standard.

**(c) Benchmarks losing relevance (in the VLA context):**
- **Meta-World** — used heavily in RL research but absent from VLA papers.
- **Robosuite/Robomimic** — restricted to the Diffusion Policy lineage; not adopted by VLA papers using language conditioning.
- **RLBench** — still dominant within the 3D-manipulation sub-field (PerAct/RVT/BridgeVLA), but the generalist VLA community (OXE-pretrained models) does not use it. RLBench's reliance on CoppeliaSim and its requirement for proprietary motion planner (MotionBenchMaker) may explain its absence from large-scale generalist training pipelines.
