# Research Progress Matrix

Topic: RLBench (CoppeliaSim) vs MuJoCo-based 로봇 학습 벤치마크
Output: `RLBench_vs_MuJoCo_Benchmarks_SURVEY.md`

## Lens (per-source extract)

- backend: 시뮬레이터/물리 엔진, 결정론, 속도, headless 지원
- scene: 씬/환경 정의 방식 (파일 포맷, 작성 난이도, 커스터마이징)
- render: 렌더링 (엔진, GPU 가속, 멀티프로세싱)
- obs_act: 관측/액션 공간, 데모 데이터 포맷, 비전+언어 어노테이션
- robot: 로봇 모델, gripper/contact 시뮬
- ecosystem: 어떤 VLA/최근 모델이 쓰는지
- ops: 설치/운영 난이도 (Docker, X server, headless)
- eval: 평가 프로토콜 (task suite, success metric, 일반화)

## Sources × Facts

| source                     | type   | relevance | backend | scene | render | obs_act | robot | ecosystem | ops | eval | repo_inspected |
|----------------------------|--------|-----------|---------|-------|--------|---------|-------|-----------|-----|------|----------------|
| RLBench                    | repo+paper | canonical | ✅      | ✅    | ✅     | ✅      | ✅    | ✅        | ✅  | ✅   | ✅ (in-repo)   |
| LIBERO                     | repo+paper | canonical | ✅      | ✅    | ✅     | ✅      | ✅    | ✅        | ✅  | ✅   | ✅              |
| Robosuite                  | repo+paper | high      | ✅      | ✅    | ✅     | ✅      | ✅    | ✅        | ✅  | ✅   | ❌ (web only)   |
| Meta-World                 | repo+paper | high      | ✅      | ✅    | ✅     | ✅      | ✅    | ✅        | ✅  | ✅   | ❌ (web only)   |
| ManiSkill 2/3              | repo+paper | high      | ✅      | ✅    | ✅     | ✅      | ✅    | ✅        | ✅  | ✅   | ❌ (web only)   |
| VLA papers (OpenVLA/π0/π0.5/Octo/RT-1/RT-2/PerAct/RVT/RVT-2/3DDA/Diffusion Policy/GR00T/BridgeVLA/Magma) | papers | high | n/a | n/a | n/a | ✅ | n/a | ✅ | n/a | ✅ | n/a |

## Phase status

- [x] Phase A: lens fixed, dirs created, progress initialized
- [x] Phase C: 4 Sonnet extraction agents returned (10-source-01..04.md written)
- [ ] Phase E: 2 Opus auditors (in progress)
- [ ] Phase F: targeted re-extraction (TBD)
- [ ] Phase G: 1 Opus consolidator
