# ultra-code · bend-groth16 (orchestrator task 72b51735, kanban #466)

Started 2026-09-18 01:22 ET. Owner reads result in the morning. Report: ~/.pika/web/reports/bend-groth16-bench-2026-09.html

## Rules (verbatim in every lane prompt)
- All code lanes Fable; verifiers/reviewers mixed Fable + gpt-6-astra. Lane names `bend-groth16 · <step> <i>/<n>`; sleeps carry `--reason "<step> i/n"`.
- Dev only under ~/dev; scratch under $TMPDIR; no bare rm (`rip`). Mini: ≤3 concurrent Rust-building lanes. Never `pkill -f`/`killall`.
- Vast.ai: label MUST start with `pika`; price < $5/h; image ghcr.io/0xandoroid/pika-vast:latest with `--login "-u 0xAndoroid -p $GITHUB_TOKEN ghcr.io"` + `--onstart-cmd /opt/pika/onstart.sh`; ONE box only; destroy with `echo y | vastai destroy instance <id>` and VERIFY gone; never touch non-pika instances. Budget ≤$40.
- Groth16 here is a benchmark subject only; nothing touches Jolt.
- Teardown at the end: no leftover processes, box destroyed, worktrees removed.

## Frozen decisions
- Curve BN254 (Fr scalar field, Fq base field). Canonical circuit `SquareChain(N)`: private x0; x_{i+1} = x_i * x_i for i<N; x_N public output. Exactly N constraints. Same circuit in every framework (arkworks, circom, gnark, bellperson).
- Sizes: full prover 2^10, 2^14, 2^18 (+2^20 for comparators if cheap). Primitives: MSM 2^10..2^20, NTT 2^10..2^20, field mul throughput.
- Data exchange format (arkworks exports, Bend consumes): `data/<log2N>/{r1cs,witness,pk,vk,proof_ref,public}.json` — hex 0x big-endian field elements, G1 `{x,y}` affine, G2 `{x:[c0,c1],y:[c0,c1]}`, infinity `{"inf":true}`. Test vectors `data/vectors/{fr_ops,fq_ops,g1_ops,g2_ops,msm_small,ntt_small}.json`. `ref verify --vk --proof --public` exit 0/1.
- Comparators (owner, 01:25): production CPU SOTA — gnark, rapidsnark, bellperson; arkworks correctness+1 CPU point; snarkjs reference only; GPU ICICLE (+ sppark if cheap) vs Bend-CUDA. Research lane confirms 2026 state.

## Wave table
| wave | shards | depends on | status |
|---|---|---|---|
| 0 | A bend-research fca3d86a (astra) · B bend-probe 9b7f93c3 (fable) · C arkworks-ref 4618ccc0 (fable) · D prover-research 150cad70 (astra) · E circom-rapidsnark e4be3580 (fable) · F bend2-probe 454fe86d (fable) | — | building (A integrated) |
| 1 | Bend field arithmetic Fr/Fq (Montgomery, limbs) + data loader · gnark bench · bellperson bench · vast box + ICICLE bench | 0 | draft |
| 2 | Bend G1/G2 ops · Bend MSM (Pippenger) · Bend NTT | 1 | draft |
| 3 | Bend groth16 prove + correctness vs arkworks verifier · CPU bench sweep · Bend-CUDA on box | 2 | draft |
| 4 | "used properly" audit (astra+fable) · report (html-report-design) · teardown | 3 | draft |

## Current wave spec (wave 0)
- A: `docs/bend-idioms.md` only. Bend/HVM2 state Sep 2026: release, numeric types (u24/i24/f24? u32/u64?), CUDA backend status, parallel idioms (fold/bend, tree recursion), IO, perf pitfalls, known bugs.
- B: `bend/probe/**`, `docs/bend-probe.md`. Install bend+hvm on the mini, measure: parallel speedup C backend (1 vs 10 threads), numeric ops, u24 mul overflow behaviour, data input path, compile time / memory ceilings.
- C: `ref/**`, `data/**` (gitignored large), `bench/arkworks-*.json`. arkworks harness per frozen format + CPU baselines.
- D: `docs/comparators.md` only. Production provers 2026 state, versions, build recipes, who runs them.
- E: `comparators/circom/**`, `bench/snarkjs-*.json`, `bench/rapidsnark-*.json`. circom SquareChain, ptau, zkey, snarkjs + rapidsnark timings.

## Amendments log
- amend: bend-lang.com now ships **Bend 2** (bendlang/bend 2.0.5, 2026-09-17; HigherOrderCO/Bend redirects). Bend 1/HVM2 (bend-lang 0.2.38 + hvm 2.0.22) is dead since 2024-08 (u24-only, 64-node CUDA def cap). PRIMARY target → Bend 2 (U32, in-place arrays, C/Metal/CUDA). Added shard w0f (Bend 2 research+probe). w0b stays on Bend 1 as a legacy data point. Report must state the version boundary.
- skip: w0a review — doc-only shard, orchestrator read sections 1–4; corrections folded by w0f if any.

## Verification matrix
| id | wave | command/probe | expected | verifier | keep/kill | evidence |
|---|---|---|---|---|---|---|

## Residuals
(none)

## Playbook
plan waves → spec wave → build → review → integrate → verify → fix(≤2) → amend → … → final review → merge main → report. Skips logged as `skip: <reason>`.
