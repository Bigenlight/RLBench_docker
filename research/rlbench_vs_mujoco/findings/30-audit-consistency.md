# Audit: Suspicious Extractions & Overall Consistency Verdict

**Audited:** 2026-05-21
**Companion to:** `30-audit-divergences.md`
**Scope:** `findings/10-source-01-rlbench.md`, `findings/10-source-02-libero.md`,
`findings/10-source-03-robosuite-metaworld-maniskill.md`,
`findings/10-source-04-vla-adoption.md`.

---

## 1. Suspicious Extractions Per Source

For each file: 1–3 claims most likely to be hallucinated, outdated, or over-asserted.

### source-01-rlbench.md (high quality, repo-inspected)

1. **"~3-5 phrasings per variation" for language annotations** `[ref: findings/10-source-01-rlbench.md §4]`
   - **Type:** Over-asserted.
   - **Why:** Source cites `close_jar.py` (4 phrasings) and `reach_target.py` (3 phrasings) as examples and generalises to "typically 3-5". The "typical" range was not verified across all 106 tasks. **Risk:** low (sampling-supported).

2. **"PerAct protocol uses 25 steps per episode (not stated in this repo — inferred from downstream paper)"** `[ref: findings/10-source-01-rlbench.md §8]`
   - **Type:** Outdated/inferred. The "25" comes from a vague reference. PerAct paper specifies max episode horizon, not "25 steps". BridgeVLA uses 25 (correct, cited). Risk: low — already labeled "inferred".

3. **"Total 108 entries in `rlbench/task_ttms/`"** `[ref: findings/10-source-01-rlbench.md §8]`
   - **Type:** Likely measurement error (see D2 in divergences). Source §2 also says "106 files" — internal inconsistency. **Risk:** medium — needs re-count.

### source-02-libero.md (high quality, repo-inspected)

1. **"CogACT (2024, ~7B) — evaluated on LIBERO [LIBERO-PRO study]"** `[ref: findings/10-source-02-libero.md §6]`
   - **Type:** **Likely hallucination or misreading.** source-04 §K (which read CogACT paper §4) confirms CogACT was evaluated on **SimplerEnv, not LIBERO**. The "[LIBERO-PRO study]" citation is suspicious — LIBERO-PRO surveys models that use LIBERO, but CogACT isn't one. **Risk: HIGH** — flagged for re-extraction.

2. **"π0 / pi0 (Black et al., Physical Intelligence, 2024) — official pi0 LIBERO checkpoint available (pi0.5 also tested in LIBERO-PRO)"** `[ref: findings/10-source-02-libero.md §6]`
   - **Type:** Missing temporal qualifier. The original π0 / π0.5 papers report **no sim evals** (source-04 §C confirms). The "official LIBERO checkpoint" is a post-publication artifact released via openpi GitHub. **Risk: medium** — fix by adding "post-publication checkpoint".

3. **"transformers==4.21.1 is quite old; newer versions may conflict with model loading"** `[ref: findings/10-source-02-libero.md §7]`
   - **Type:** Over-asserted generalization. The "may conflict" is opinion not grounded in evidence from the LIBERO repo or issues. **Risk:** low — minor speculative claim.

### source-03-robosuite-metaworld-maniskill.md (no repo cloned — web-only sources)

1. **"OpenVLA … robosuite environments are part of the eval harness used by the OpenVLA team via robomimic pipelines"** `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.6]`
   - **Type:** **Hallucination.** source-04 §A (which read OpenVLA paper Appendix E) says OpenVLA evaluated on **LIBERO only** in sim. The robosuite-via-robomimic claim is **not in the OpenVLA paper**. Likely a confused attribution. **Risk: HIGH** — re-extract.

2. **"Octo (2024, arXiv:2405.12213): Generalist policy fine-tuned on robosuite-based environments"** AND "Octo … evaluated using ManiSkill3 environments; listed as integrated baseline" `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.6 and §C.6]`
   - **Type:** **Hallucination / conflation.** source-04 §D (which read Octo paper) confirms Octo has **zero sim benchmark numbers**. ManiSkill3 ships a *baseline implementation* of Octo (different from Octo paper-reported evals). **Risk: HIGH** — re-extract both passages.

3. **"Diffusion Policy (RSS 2023, arXiv:2303.04137): Used Meta-World tasks (state-based) as part of its 12-task evaluation … ManiSkill2" (the same DP paper appears as eval-on-ManiSkill2 in §C.6)** `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §B.6 and §C.6]`
   - **Type:** **Hallucination.** source-04 §I enumerates the DP paper's 4 benchmarks: **Robomimic, Push-T, BET-Block-Pushing, Franka Kitchen** — Meta-World and ManiSkill2 are NOT among them. The "12 tasks across 4 benchmarks" quote applies to those four, not Meta-World/ManiSkill. **Risk: HIGH** — re-extract.

4. **"MuJoCo … MIT licence"** `[ref: findings/10-source-03-robosuite-metaworld-maniskill.md §A.7]`
   - **Type:** Factually wrong. DeepMind released MuJoCo under **Apache 2.0**, not MIT (source-02 §7 correctly says Apache 2.0). **Risk: medium** — easy fix.

### source-04-vla-adoption.md (paper-cited, well-grounded)

1. **"OpenVLA-OFT (arXiv:2502.19645) recipe raises this to 97.1%"** `[ref: findings/10-source-04-vla-adoption.md §A]`
   - **Type:** Number citation — plausible but unverified by us. Risk: low.

2. **"vla-eval unified harness (arXiv:2603.13966)"** `[ref: findings/10-source-04-vla-adoption.md §LIBERO ranking section]`
   - **Type:** **Suspicious arXiv ID — '2603' = year 2026 March which is in the future at extraction time (May 2026 is plausible but '2603' is *early* 2026)**. Check the arXiv ID — possibly a typo (should be 2503 / 2506 / similar). **Risk: medium** — need to verify the ID and the harness's existence.

3. **"LIBERO-PRO (arXiv:2510.03827, Oct 2024)"** `[ref: findings/10-source-04-vla-adoption.md §LIBERO ranking section, also source-02 §6]`
   - **Type:** **Date / ID mismatch.** arXiv ID 2510 = year 2025 month 10 (Oct 2025), NOT Oct 2024. Both source-02 and source-04 cite this paper but date it wrong. **Risk: medium** — fix the date in both files.

---

## 2. Overall Consistency Verdict

### Verdict: **MEDIUM**

**Reasoning:**
- **Sources 01, 02, 04 are high-quality** with repo inspection or paper-grounded citations. Their internal claims align well.
- **Source 03 is the weak link.** It was extracted from web sources / docs without cloning the repos, and it contains 4 significant factual errors:
  1. OpenVLA → robosuite eval (D4)
  2. Octo → robosuite/ManiSkill eval (D22)
  3. Diffusion Policy → Meta-World/ManiSkill eval (D16)
  4. MuJoCo licence type (D13)
- These errors are not random typos — they appear to be **misattributions of benchmark integrations** (i.e., the benchmark ships a baseline for model X) as **paper-reported evaluations by model X**. This is a systematic error pattern in source-03's §A.6, §B.6, §C.6 ecosystem sections.
- Internal inconsistencies are minor (source-01's TTM count off-by-one; source-03's arm count). Easy fixes.
- Versioning divergences (RLBench 100 vs 106 tasks; robosuite 1.4 vs 1.5 mujoco pin) are real and survey-worthy — not errors.

### What raises the verdict above LOW
- Source-04 acts as a strong cross-check for VLA adoption claims and explicitly notes ambiguities (e.g., "GitHub issue mentions LIBERO eval but official whitepaper does not report").
- Sources 01 and 02 cite specific file paths and line numbers, easy to spot-verify.
- The single key mechanical fact your audit checks for (ManiSkill physics = SAPIEN/PhysX, not MuJoCo) **passed cleanly**.

### What prevents HIGH
- Source-03's ecosystem section needs ~4 corrections. Without those, the consolidated survey would inherit benchmark-adoption errors.
- Two arXiv ID/date metadata issues in source-04 (vla-eval and LIBERO-PRO dates).

---

## 3. Phase F Re-extraction Recommendations (Prioritized)

### Top priority

1. **source-03 §A.6 (Robosuite ecosystem):** Remove or qualify the OpenVLA-on-robosuite claim. Verify by reading OpenVLA paper §5 and Appendix E directly. Truth: OpenVLA sim eval = LIBERO only.

2. **source-03 §A.6 and §C.6 (Octo on robosuite / ManiSkill):** Remove. Replace with "Octo paper reports no sim benchmark evals; ManiSkill3 ships an Octo *baseline implementation* but Octo paper §4 evaluates on 9 real-robot setups only."

3. **source-03 §B.6 and §C.6 (Diffusion Policy on Meta-World / ManiSkill):** Remove. Replace with: "Diffusion Policy (arXiv:2303.04137) evaluates on 4 benchmarks: Robomimic, Push-T, BET-Block-Pushing, and Franka Kitchen. Meta-World and ManiSkill are NOT among the 4."

### Medium priority

4. **source-02 §6 (CogACT on LIBERO):** Either provide a primary citation from CogACT paper showing LIBERO numbers, or remove. source-04 indicates CogACT paper §4 evaluates only on SimplerEnv.

5. **source-02 §6 (π0 / π0.5 on LIBERO):** Add qualifier "post-publication checkpoint released via openpi GitHub; not in original paper" — matching source-04's framing.

6. **source-03 §A.7 (MuJoCo licence):** Change "MIT" → "Apache 2.0".

### Low priority (housekeeping)

7. **source-01 §2 / §8 (TTM file count):** Reconcile — actual count by `ls rlbench/task_ttms/*.ttm | wc -l`. Possibly 106 vs 108 due to including/excluding `.ttm` extensions or hidden files.

8. **source-03 §A.5 Summary (RLBench arms list):** Add Jaco to the list "Panda/Sawyer/UR5/Mico" → "Panda/Jaco/Mico/Sawyer/UR5".

9. **source-04 (arXiv ID metadata):**
   - Verify arXiv:2603.13966 (vla-eval) — likely a typo, check actual ID.
   - LIBERO-PRO is arXiv:2510.03827, which decodes to **Oct 2025** (not Oct 2024). Fix dates in source-02 §6 and source-04 LIBERO-ranking section.

10. **source-03 §A.5 Summary (Robosuite arm count "10 arm types"):** Internally inconsistent — table includes GR1/Spot/Tiago. Clarify: "10 robots total in v1.5 (7 single-arm + GR1 humanoid + Spot + Tiago mobile)".

---

## 4. What's NOT broken (good news)

- **ManiSkill = SAPIEN + PhysX (not MuJoCo)**: consistent across source-03 and source-04. Audit checkpoint passed.
- **RLBench task count divergence (100 paper / 106 repo HEAD)**: properly framed as versioning, not error.
- **LIBERO suite structure (10/10/10/90/10 = 130 tasks)**: source-02 self-consistent and matches paper.
- **PerAct/RVT/RVT-2/3DDA/BridgeVLA all on RLBench**: source-01 and source-04 agree.
- **OpenVLA / Magma on LIBERO**: source-02 and source-04 agree.
- **MuJoCo open-source date (Oct 2021)**: consistent across source-02 and source-03 (only the licence-name differs).
- **CoppeliaSim 4.1.0 Edu pin for RLBench**: self-consistent in source-01.

---

*Companion file: see `30-audit-divergences.md` for the full divergences table.*
