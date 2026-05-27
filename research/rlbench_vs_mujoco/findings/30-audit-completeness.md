# Phase E — Completeness Audit

**Auditor role:** Completeness check across (lens axis × source) for RLBench vs MuJoCo-based benchmarks survey.
**Date:** 2026-05-21
**Findings audited:**
- `findings/10-source-01-rlbench.md`
- `findings/10-source-02-libero.md`
- `findings/10-source-03-robosuite-metaworld-maniskill.md` (split into 03A Robosuite / 03B Meta-World / 03C ManiSkill)
- `findings/10-source-04-vla-adoption.md`

---

## 1. Coverage matrix

Legend: `full` = concrete details + citations; `partial` = some info, missing key sub-facets; `none` = essentially missing; `n/a` = inapplicable for that source.

| axis | RLBench (01) | LIBERO (02) | Robosuite (03A) | Meta-World (03B) | ManiSkill (03C) | VLA papers (04) |
|---|---|---|---|---|---|---|
| **simulator_backend** (engine, determinism, sim speed, headless) | full [ref: findings/10-source-01-rlbench.md §1] | full [ref: findings/10-source-02-libero.md §1] | partial — sim_freq inferred, no measured FPS [ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.1] | partial — sim/control rate "assumed", no FPS [ref: findings/10-source-03-...md §B.1] | full — FPS, determinism, headless all covered [ref: findings/10-source-03-...md §C.1] | n/a |
| **scene_format** (file format, authoring difficulty) | full [ref: findings/10-source-01-rlbench.md §2] | full — BDDL DSL, programmatic gen, MJCF assets [ref: findings/10-source-02-libero.md §2] | full — MJCF + modular composer [ref: findings/10-source-03-...md §A.2] | partial — MJCF noted but no asset library size, no example [ref: findings/10-source-03-...md §B.2] | full — URDF + MJCF + object lib size [ref: findings/10-source-03-...md §C.2] | n/a |
| **rendering** (engine, GPU, multiproc) | full [ref: findings/10-source-01-rlbench.md §3] | full — EGL, SubprocVectorEnv, resolution [ref: findings/10-source-02-libero.md §3] | full — EGL, Isaac Sim, multi-cam [ref: findings/10-source-03-...md §A.3] | partial — EGL noted, no res, no multi-cam detail, no vectorization [ref: findings/10-source-03-...md §B.3] | full — Vulkan, 30k FPS, parallel render [ref: findings/10-source-03-...md §C.3] | n/a |
| **observation_action_space** (obs, demo format, language) | full — HDF5-equivalent pickle+PNG, NL native [ref: findings/10-source-01-rlbench.md §4] | full — HDF5 schema, BERT/CLIP encoders, 50 demos/task [ref: findings/10-source-02-libero.md §4] | full — HDF5 via robomimic, 6 controllers [ref: findings/10-source-03-...md §A.4] | partial — no demo dataset (genuine n/a for demos); obs/act covered [ref: findings/10-source-03-...md §B.4] | full — HDF5 naming, demo scale [ref: findings/10-source-03-...md §C.4] | full — which benchmarks each VLA evaluates on, demo counts [ref: findings/10-source-04-vla-adoption.md §A–K2] |
| **robot_models** (arm/gripper, contact) | full — 5 arms, grasp-hack noted [ref: findings/10-source-01-rlbench.md §5] | partial — Panda only, table friction; no detailed contact model discussion [ref: findings/10-source-02-libero.md §5] | full — 10 robots + 9 grippers + 4 bases [ref: findings/10-source-03-...md §A.5] | full — Sawyer-only explicitly stated as limit [ref: findings/10-source-03-...md §B.5] | full — 20+ robots across categories [ref: findings/10-source-03-...md §C.5] | n/a |
| **ecosystem** (which VLAs use it) | full — 6 papers cited with task counts [ref: findings/10-source-01-rlbench.md §6] | full — OpenVLA, π0, CogACT, Magma listed; HF datasets [ref: findings/10-source-02-libero.md §6] | full — robomimic, MimicGen, Diffusion Policy, OpenVLA path [ref: findings/10-source-03-...md §A.6] | full — RL-heavy, almost no VLA use stated [ref: findings/10-source-03-...md §B.6] | full — TD-MPC2, Octo, RDT-1B, RT-X [ref: findings/10-source-03-...md §C.6] | full — model×benchmark matrix [ref: findings/10-source-04-vla-adoption.md §Summary Table] |
| **install_ops** (Docker, X, headless pain) | full — Dockerfile, QT_PLUGIN_PATH gotcha, 6 breakage points [ref: findings/10-source-01-rlbench.md §7] | full — pinned versions, EGL, no Docker noted [ref: findings/10-source-02-libero.md §7] | partial — install snippet but no Docker, no detailed breakage list [ref: findings/10-source-03-...md §A.7] | partial — pip install line + EGL; no version pins, no breakage list [ref: findings/10-source-03-...md §B.7] | full — Vulkan dep, official Docker image, platform matrix [ref: findings/10-source-03-...md §C.7] | n/a |
| **eval_protocol** (tasks, metric, variations) | full — 106 tasks, PerAct-18, variations enumerated [ref: findings/10-source-01-rlbench.md §8] | full — 130 tasks, 4 suites, 50 demos, 20 rollouts, lifelong protocol [ref: findings/10-source-02-libero.md §8] | full — 9 standard + 18 MimicGen tasks, 200 demos baseline [ref: findings/10-source-03-...md §A.8] | full — MT1/10/50, ML1/10/45, IQM metric [ref: findings/10-source-03-...md §B.8] | partial — MS3 exact task count "not precisely enumerated" [ref: findings/10-source-03-...md §C.8] | full — per-paper eval setups in §A–K2 + §Trends |

---

## 2. Re-run shortlist (Phase F candidates)

Sorted by **impact for the final RLBench-vs-MuJoCo survey**. Max 6.

1. **source-03A (Robosuite) needs install_ops Docker / breakage detail** — RLBench's section 1 advantage in the survey is the painful Docker story; without a matching "MuJoCo-side install is easy" concrete claim (no Dockerfile, no Qt fix, no version pin) the install-pain contrast is asymmetric. [gap: ref findings/10-source-03-...md §A.7]
2. **source-03B (Meta-World) needs control/sim FPS + sim speed** — Speed is one of the headline RLBench weaknesses; Meta-World's speed advantage is asserted but no numeric anchor exists. [gap: ref findings/10-source-03-...md §B.1]
3. **source-03A (Robosuite) needs measured sim FPS** — Same reason; "MuJoCo orders of magnitude faster" is claimed in the §A summary but unmeasured. Needed for the speed comparison column. [gap: ref findings/10-source-03-...md §A.1 vs §Summary A.1]
4. **source-03C (ManiSkill) needs MS3 exact task count + per-task demo counts** — Eval-protocol axis must be apples-to-apples (RLBench 18, LIBERO 130, MS3 ?). Currently "12 domains, total not precisely enumerated". [gap: ref findings/10-source-03-...md §C.8]
5. **source-02 (LIBERO) needs MuJoCo contact-model specifics (timestep, integrator, solver)** — Needed for the "contact simulation" robot column to contrast vs RLBench's grasp-hack. Currently only friction tuple is given. [gap: ref findings/10-source-02-libero.md §5]
6. **source-03B (Meta-World) needs image-mode rendering details (resolution, multi-cam)** — Currently dismissed as "state-based by default", but for completeness of the rendering axis a one-line "image mode supports X resolution, Y cameras" is needed. [gap: ref findings/10-source-03-...md §B.3]

### Likely-not-extractable

- **Robosuite/Meta-World measured FPS on standardized hardware** — Not pinned in public docs; would require running the sims. Mark as "literature does not report".
- **Cross-platform bitwise determinism for MuJoCo / SAPIEN-PhysX** — Public docs state determinism is best-effort; no formal guarantee in any benchmark's docs.
- **Meta-World official demo dataset** — Confirmed in §B.4 that none exists; this is a genuine null, not a gap.

---

## 3. Source classification

| Source | Classification | Notes |
|---|---|---|
| 10-source-01-rlbench.md | `eval-on-topic` | Canonical comparator anchor; in-repo inspection + paper |
| 10-source-02-libero.md | `eval-on-topic` | Direct MuJoCo-based comparator; cloned repo + paper |
| 10-source-03A Robosuite | `eval-on-topic` | Direct MuJoCo comparator; web/docs only (no repo clone) |
| 10-source-03B Meta-World | `eval-on-topic` | Direct MuJoCo comparator; web/docs only |
| 10-source-03C ManiSkill | `eval-on-topic` (with caveat) | **Caveat: not MuJoCo — uses SAPIEN/PhysX.** Still on-topic as a comparator MuJoCo-adjacent benchmark, but the survey must flag this clearly. The progress file groups it under "MuJoCo-based" which is **inaccurate** — should be re-labeled "open-source-physics manipulation benchmarks" or split out. [ref: findings/10-source-03-...md §C.1, version note]
| 10-source-04-vla-adoption.md | `eval-on-topic` | Per-paper benchmark adoption matrix — exactly what the ecosystem axis needs |

**Flag:** ManiSkill is mis-grouped in `_progress.md` as MuJoCo-based; survey draft must correct this.

---

## 4. Verdict

**Overall completeness: HIGH.**

- 6 of 8 lens axes have `full` coverage for ≥4 of the 5 benchmark sources.
- The two weakest axes (`install_ops`, `simulator_backend`) are weak only on the **web-only sources** (Robosuite, Meta-World), which is expected — local repo inspection was only done for RLBench and LIBERO.
- VLA-paper source (04) is comprehensively cross-referenced.
- No `none` cells; only `partial` gaps in well-bounded sub-facets.

**Phase F necessity: OPTIONAL / LOW.**

Phase F is **not strictly required** to write the survey. The 6 shortlisted re-runs would polish the comparison columns (especially the speed and install-pain symmetry) but are not blockers. Recommend a **lightweight Phase F**: one Sonnet pass to fill items 1–3 only (Robosuite + Meta-World ops/FPS). Items 4–6 can be flagged as "not reported in surveyed sources" in the survey body.

**One must-fix before Phase G:** Re-label ManiSkill as SAPIEN/PhysX-based (not MuJoCo) in the progress matrix and in any column header that says "MuJoCo benchmarks". Otherwise the survey's framing is incorrect.

---

*End of audit.*
