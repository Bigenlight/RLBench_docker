# Audit: Divergences Across Sources 01–04

**Audited:** 2026-05-21
**Scope:** `findings/10-source-01-rlbench.md`, `findings/10-source-02-libero.md`,
`findings/10-source-03-robosuite-metaworld-maniskill.md`,
`findings/10-source-04-vla-adoption.md`.
**Cross-citation form:** `[ref: findings/10-source-XX-name.md §<section>]`.

---

## 1. Divergences Table

| # | claim type | source A | claim A | source B | claim B | likely cause / resolution |
|---|---|---|---|---|---|---|
| D1 | RLBench task count | source-01 §8 | "Paper claims **100 tasks**" | source-01 §8 / source-03 Summary B.2 | "Repo contains **106 task Python files**" / "RLBench has 100 tasks" | **Known versioning divergence.** Paper (2020) reports 100; repo HEAD has 106 (6 added since). source-03 echoes the paper number. Resolution: in survey, report "100 (paper) / 106 (repo HEAD 2025)". |
| D2 | RLBench task TTM count | source-01 §2 | "Stored in `rlbench/task_ttms/` (106 files)" | source-01 §8 | "**108 entries** in `rlbench/task_ttms/` (including `__init__.py` = 107 non-init)" | **Internal inconsistency in source-01.** §2 says 106 files, §8 says 107 non-init. Resolution: re-extract; verify by listing `rlbench/task_ttms/*.ttm` exactly. |
| D3 | RLBench language annotation count per variation | source-01 §4 | "3-5 phrasings per variation" (typical) | source-01 §6 / source-02 §summary | RLBench has "native language annotation" but no head-count given by source-02 | Minor — source-02 says RLBench has "far fewer VLA paper evaluations", but that's about ecosystem, not annotation count. No real divergence — just precise number ("3-5") in source-01 is anecdotal. Resolution: keep "multiple phrasings per variation" without exact count. |
| D4 | OpenVLA evals on RLBench | source-04 §A table | "OpenVLA: RLBench = —" (not evaluated) | source-03 §Robosuite ecosystem | "OpenVLA … robosuite environments are part of the eval harness used by the OpenVLA team via robomimic pipelines" | **High-priority divergence.** source-04 (which actually read the OpenVLA paper Appendix E) says **LIBERO only**. source-03's claim that OpenVLA evaluates on Robosuite is **unverified speculation** — OpenVLA's published evals are LIBERO (4 suites) + real-robot only. Resolution: source-03 §A.6 should be corrected — OpenVLA does **not** use robosuite as an eval harness in the paper. Phase F re-extract needed. |
| D5 | Robosuite MuJoCo version | source-02 §1 | "robosuite==1.4.0; Robosuite 1.4.0 itself requires `mujoco>=2.2.0` (newer binding)" | source-03 §A.1 | "MuJoCo ≥ 2.3 is assumed by current tooling" | **Version drift, not contradiction.** source-02 reads LIBERO's pin (robosuite 1.4.0 → mujoco ≥2.2). source-03 refers to current robosuite v1.5 in robosuite.ai docs, which assumes ≥2.3. Resolution: tag clearly — robosuite 1.4 needs mujoco≥2.2; robosuite 1.5 assumes ≥2.3. |
| D6 | Robosuite arm count | source-03 §A.5 | "10 manipulators" in v1.5 | source-03 §A.5 detail vs Summary §A.3 | Summary A.3 lists "10 arm types + GR1 humanoid + wheeled/legged bases vs RLBench's Panda/Sawyer/UR5/Mico only" | **Internal inconsistency in source-03.** Table lists 10 robots **including** GR1, Spot, Tiago (humanoid/mobile, not "arm"). Summary §A.3 says "10 arm types **+** GR1 humanoid", implying 10 are arms and GR1 is extra. Resolution: re-extract; the table appears authoritative — 10 robots total, ~7 are tabletop arms. |
| D7 | RLBench supported robots vs source-03 summary | source-01 §5 | Panda, Jaco, Mico, Sawyer, UR5 (5 robots, in `SUPPORTED_ROBOTS`) | source-03 Summary §A.3 | "RLBench's Panda/Sawyer/UR5/Mico only" (4 robots listed, Jaco missing) | source-03's summary omitted Jaco. Resolution: correct source-03 summary to "Panda/Jaco/Mico/Sawyer/UR5". |
| D8 | RLBench default image resolution | source-01 §3 | "128×128" | not contradicted by any other source | n/a | No divergence. |
| D9 | LIBERO control freq | source-02 §1 | "control_freq=20 Hz" | source-03 §A.1 | Robosuite default "control_freq = 20 Hz" | Consistent — LIBERO inherits robosuite default. |
| D10 | LIBERO demos per task | source-02 §4 / §8 | "50 demos per task" | source-04 §A | "10 tasks × 50 rollouts per task" (about *eval rollouts*, not demos, but cited demo paper has 50) | Consistent — 50 demos at train, 20 eval rollouts (source-02 §8 `env_num=20`), but OpenVLA paper used 500 rollouts (3 seeds × 500) — different from LIBERO default protocol. Note: OpenVLA used non-default eval protocol; flag for Phase F. |
| D11 | Robosuite "standard tasks" count | source-03 §A.8 | "Standard benchmark tasks (**9**)" enumerated | source-03 §A.6 | "MimicGen … 18 tasks" — adds 18 *additional* tasks to robosuite | Consistent — 9 base + 18 MimicGen = 27. Just clarify in survey. |
| D12 | ManiSkill physics engine | source-03 §C.1 (version note) | "ManiSkill 3 … uses **SAPIEN + PhysX** (not MuJoCo). ManiSkill 2 … also used SAPIEN + PhysX" | source-04 §K (CogACT) | "SimplerEnv … built on ManiSkill2/SAPIEN" | Consistent — both sources agree ManiSkill is SAPIEN/PhysX. **Good — no contradiction.** This was a key audit checkpoint and it passed. |
| D13 | MuJoCo licence date | source-02 §7 | "October 2021, v2.1.0+" Apache 2.0 | source-03 §A.7 | "Free / open-source since October 2021 (MIT licence)" | **License-name contradiction.** Apache 2.0 vs MIT. Truth: DeepMind released MuJoCo under **Apache 2.0**. source-03 is wrong — Resolution: correct source-03 to Apache 2.0. |
| D14 | Robosuite demo collection device list | source-03 §A.4 | "keyboard, SpaceMouse, DualSense controller, MuJoCo viewer drag-drop" | none | n/a | No divergence; unverified but plausible. |
| D15 | Meta-World task count | source-03 §B.8 | MT50 = "50 tasks"; "All 50 Sawyer environments" | source-04 (no mention) | n/a | Consistent with general knowledge. |
| D16 | Diffusion Policy benchmarks | source-04 §I | Robomimic, Push-T, Block Pushing, Franka Kitchen (**4**) | source-03 §A.6 + §B.6 + §C.6 | "Diffusion Policy … 12 tasks across 4 benchmarks … including robosuite" and "Metaworld" and "ManiSkill2" | **Direct contradiction.** source-04 enumerates the 4 benchmarks Diffusion Policy uses: Robomimic / Push-T / BET-Block-Pushing / Franka-Kitchen. source-03 §B.6 (Meta-World) and §C.6 (ManiSkill) both say Diffusion Policy "evaluated on" them. This is **wrong** — re-reading the DP abstract: "12 tasks across 4 benchmarks" — those 4 are Robomimic, Push-T, BET, Franka Kitchen. Meta-World and ManiSkill are NOT among them. Resolution: source-03 needs correction in §B.6 and §C.6. **High-priority.** |
| D17 | BridgeVLA — LIBERO eval | source-02 §6 | "Not confirmed on LIBERO: BridgeVLA (not found in search)" | source-04 §E | "BridgeVLA … LIBERO, Robosuite, Meta-World, ManiSkill: **not evaluated**" | Consistent — both agree BridgeVLA does not eval on LIBERO. Resolution: no action. |
| D18 | BridgeVLA RLBench result | source-01 §6 | "88.2% avg success on RLBench, 64.0% on COLOSSEUM" | source-04 §E | "88.2% (up from 81.4% SOTA)" RLBench; "64.0%" COLOSSEUM | Consistent. Resolution: no action. |
| D19 | RVT-2 result on RLBench | source-01 §6 | "82% avg success (from 65%)" | source-04 §H | "from 65% to 82%" | Consistent. |
| D20 | PerAct task subset | source-01 §6, §8 | "18 tasks, 249 variations" | source-04 §G | "18 RLBench tasks (with 249 variations)" | Consistent. |
| D21 | 3D Diffuser Actor RLBench gain | source-01 §6 | "+18.1% abs over SOTA on RLBench multi-view" | source-04 §J | "**18.1% absolute gain** over prior SOTA (multi-view)" | Consistent. |
| D22 | Octo — sim eval status | source-04 §D | "**None** — focuses entirely on real-robot" | source-03 §A.6 | "Octo (2024, arXiv:2405.12213): Generalist policy fine-tuned on robosuite-based environments." | **High-priority contradiction.** source-04 (which actually read Octo paper) says Octo has **zero sim benchmark numbers** in the paper. source-03 claims Octo was "fine-tuned on robosuite-based environments". The Octo paper §4 explicitly evaluates on 9 real-robot setups; no robosuite numbers. source-03 also claims "Octo … evaluated using ManiSkill3 environments; listed as integrated baseline" (§C.6) — this conflates ManiSkill's *baseline implementations* with Octo's *paper-reported evals*. Resolution: source-03 needs correction in §A.6 (Octo) and §C.6 (Octo). |
| D23 | RT-X Open X-Embodiment trajectories | source-03 §A.6 | implies robosuite trajectories appear in OXE | source-04 §B (RT-X) | "9 manipulators … from RT-1, QT-Opt, Bridge, Task Agnostic Robot Play, Jaco Play, Cable Routing, RoboTurk, NYU VINN, Austin VIOLA, Berkeley Autolab UR5, TOTO and Language Table" | **Hallucination in source-03.** Robosuite-collected trajectories are not directly enumerated in the OXE list per source-04. Some of those datasets (RoboTurk) are loosely related to robosuite (RoboTurk system → robosuite data) but source-03 overstates the link. Resolution: soften source-03's claim to "RoboTurk uses robosuite as its simulator, so some OXE data is robosuite-collected" — but not "robosuite trajectories appear in OXE" without specifics. |
| D24 | OpenVLA training data size | source-03 §A.6 | "Open X-Embodiment (970k trajectories)" | source-04 §A | "970k real-world robot demonstrations" | Consistent. |
| D25 | ManiSkill 3 FPS | source-03 §C.3 | "Up to **30,000+ FPS**" RGBD on RTX 4090 | not contradicted | n/a | Consistent with arXiv:2410.00425. |

---

## 2. Cross-Validation: VLA × Benchmark Matrix

### Models that source-01 (RLBench) lists as RLBench users

| Model (source-01 §6) | source-04 master table says | Agreement? |
|---|---|---|
| PerAct | ✓ RLBench | **Agree** |
| RVT | ✓ RLBench | **Agree** |
| RVT-2 | ✓ RLBench | **Agree** |
| Act3D | (not in source-04 table) | source-04 omits Act3D — minor gap, not contradiction |
| 3D Diffuser Actor | ✓ RLBench, ✓ CALVIN | **Agree** (source-01 also notes CALVIN) |
| BridgeVLA | ✓ RLBench | **Agree** |
| Hiveformer (source-01 §6 unconfirmed) | absent from source-04 | Both flag it as unverified — consistent |
| ARP (source-01 §6 unconfirmed) | absent from source-04 | Both flag it as unverified — consistent |

**Verdict:** source-01 and source-04 agree on the RLBench user list. No divergence.

### Models that source-02 (LIBERO) lists as LIBERO users

| Model (source-02 §6) | source-04 master table says | Agreement? |
|---|---|---|
| OpenVLA | ✓ LIBERO | **Agree** |
| π0 / pi0 | source-04 §C: "post-publication checkpoint", original paper has **no sim evals** | **Partial divergence.** source-02 says π0 evaluated on LIBERO; source-04 clarifies this is a post-pub checkpoint not in the original paper. **Action: source-02 should add the "post-publication" qualifier.** |
| CogACT | source-04 §K: SimplerEnv only, **not LIBERO** | **Direct contradiction.** source-02 claims CogACT evaluated on LIBERO (citing "LIBERO-PRO study"); source-04 (citing CogACT paper §4) says SimplerEnv only. Source-02 may be reading LIBERO-PRO's secondary citations rather than the CogACT paper itself. **Action: source-02 should remove or qualify CogACT-LIBERO claim.** |
| Magma | ✓ LIBERO | **Agree** |
| RoboFlamingo | source-04 absent | source-04 omits RoboFlamingo — gap, not contradiction |
| MimicPlay | source-04 absent | source-04 omits MimicPlay — gap |
| MUTEX | source-04 absent | gap |
| TAIL | source-04 absent | gap |
| Diffusion Policy (via LeRobot/HF) | source-04 §I: Robomimic, Push-T, BET, Franka Kitchen — **not LIBERO** | **Soft divergence.** source-02 cites HF/LeRobot integration (not paper eval); source-04 cites the paper. Both can be true. Resolution: source-02 should clarify "via LeRobot ports, not original paper". |
| π0.5 | source-04 §C: **None**; post-pub LIBERO checkpoint exists | Same partial divergence as π0. |

### Models source-04 says "no sim eval" but other sources claim used a benchmark

- **High-priority:** source-03 says Octo was "fine-tuned on robosuite-based environments" (D22 above), but source-04 says Octo evaluated on real robots only. **source-03 incorrect.**
- **High-priority:** source-03 says OpenVLA uses robosuite eval harness (D4 above); source-04 says OpenVLA = LIBERO only. **source-03 incorrect.**
- **Medium:** source-02 lists CogACT on LIBERO; source-04 says CogACT = SimplerEnv only. **source-02 likely incorrect.**

---

## 3. Other Notable Findings From the Audit

### a. ManiSkill physics engine audit (your specific request)
**Verified clean.** Both source-03 §C.1 and source-04 §K (CogACT, SimplerEnv) consistently say ManiSkill 2/3 use SAPIEN + PhysX, **not MuJoCo**. source-03 explicitly flags this in a "version note" callout at the top of §C. No contradiction.

### b. mujoco-py vs mujoco binding audit
- source-02 §7 explicitly states LIBERO uses the new `mujoco` Python binding, not mujoco-py. Robosuite 1.4.0+ also requires the new binding.
- source-03 §B.7 (Meta-World) notes Meta-World+ "is a drop-in replacement fixing the deprecated `mujoco-py` / OpenAI Gym dependency". The original Meta-World had mujoco-py; current Meta-World+ uses `mujoco`.
- **No contradiction**, but a survey-worthy nuance: old MuJoCo-based benchmarks (pre-2022) used mujoco-py; current versions all use `mujoco`. This affects reproducibility of older VLA papers (e.g., if a 2022 paper cites Meta-World mujoco-py, today's Meta-World+ may give different numbers).

### c. RLBench's CoppeliaSim version pinning
- source-01 §1 and §7 both consistently pin CoppeliaSim 4.1.0 Edu. No divergence.

### d. CoppeliaSim has MuJoCo as one of 5 physics engines (interesting fact in source-01 §1)
- source-01 §1 notes CoppeliaSim ships with Bullet/ODE/Vortex/Newton/MuJoCo. Default engine for RLBench is embedded in `.ttt` file (not stated which).
- **No other source mentions this.** Survey-worthy: even RLBench *could* run with MuJoCo physics, but the default has not been verified. Source-01 explicitly says "Not stated in Python source" — flagged as a known gap.

---

## 4. Quantitative Summary

- Total claim-pairs audited: 25
- **Direct contradictions:** 5 (D4, D6, D13, D16, D22) — all involve source-03 over-asserting VLA → benchmark adoption
- **Partial divergences / qualifier missing:** 4 (D10 protocol mismatch; source-02 π0/π0.5/CogACT/DP needing qualifiers)
- **Internal inconsistencies within one source:** 2 (D2 source-01 TTM count, D6 source-03 arm count)
- **Version-drift (both true at their time):** 2 (D1 RLBench task count, D5 mujoco version)
- **Consistent / no action needed:** 12

---

*See `30-audit-consistency.md` for suspicious-extraction list and overall consistency verdict.*
