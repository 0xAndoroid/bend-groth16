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
| 0 | A bend-research fca3d86a (astra) · B bend-probe 9b7f93c3 (fable) · C arkworks-ref 4618ccc0 (fable) · D prover-research 150cad70 (astra) · E circom-rapidsnark e4be3580 (fable) · F bend2-probe 454fe86d (fable) · review C 2b106e2c · review B 401804b1 (astra) | — | building (all integrated) |
| 1 | gnark-mini 8e7167e8 (fable) · gpu-box 6b6fc33c (fable: rent pika-bend-5090, box-CPU gnark/rapidsnark/snarkjs, GPU gnark+icicle, ICICLE-SNARK, ICICLE/sppark primitives, Bend 2 install) · [after w0f] bend2-field-curve 41379b12 (Fr/Fq/Fq2/G1/G2 + tests + field bench) · bend2-export 53ed8004 (integrated; K=18 export 4.3 s, 308 MB, 0 round-trip mismatches) · review gnark ebecad7b | 0 | gnark integrated; box + bend2 lanes building |
| 2 | Bend MSM (Pippenger, G1 then G2) · Bend NTT + QAP h-poly · loader/prover skeleton | 1 | draft |
| 3 | Bend groth16 prove + correctness vs arkworks verifier · CPU bench sweep · Bend-CUDA on box | 2 | draft |
| 4 | quiet-host CPU bench rerun (all mini comparators + Bend, serial) · "used properly" audit (astra+fable) · report (html-report-design) · teardown | 3 | draft |

## Current wave spec (wave 0)
- A: `docs/bend-idioms.md` only. Bend/HVM2 state Sep 2026: release, numeric types (u24/i24/f24? u32/u64?), CUDA backend status, parallel idioms (fold/bend, tree recursion), IO, perf pitfalls, known bugs.
- B: `bend/probe/**`, `docs/bend-probe.md`. Install bend+hvm on the mini, measure: parallel speedup C backend (1 vs 10 threads), numeric ops, u24 mul overflow behaviour, data input path, compile time / memory ceilings.
- C: `ref/**`, `data/**` (gitignored large), `bench/arkworks-*.json`. arkworks harness per frozen format + CPU baselines.
- D: `docs/comparators.md` only. Production provers 2026 state, versions, build recipes, who runs them.
- E: `comparators/circom/**`, `bench/snarkjs-*.json`, `bench/rapidsnark-*.json`. circom SquareChain, ptau, zkey, snarkjs + rapidsnark timings.

## Amendments log
- amend: bend-lang.com now ships **Bend 2** (bendlang/bend 2.0.5, 2026-09-17; HigherOrderCO/Bend redirects). Bend 1/HVM2 (bend-lang 0.2.38 + hvm 2.0.22) is dead since 2024-08 (u24-only, 64-node CUDA def cap). PRIMARY target → Bend 2 (U32, in-place arrays, C/Metal/CUDA). Added shard w0f (Bend 2 research+probe). w0b stays on Bend 1 as a legacy data point. Report must state the version boundary.
- amend: comparators per w0d — CPU gnark v0.16.3 + rapidsnark v0.0.8 (+snarkjs ref, arkworks ref); GPU gnark+icicle-gnark v3.2.2 + ICICLE-SNARK bf00385 (experimental) + ICICLE v4/sppark BN254 primitives. bellperson dropped (BLS12-381 only), bellman-ce archived. w0d merged (doc-only; skip review, orchestrator read).
- skip: w0e per-shard review — scripts shard; covered by the quiet-host rerun lane (re-executes gen.sh/bench.py) + final whole-diff review.
- amend: ownership overlap .gitignore between w0e,w1gnark (both append-only) — resolved by union; .gitignore stays orchestrator-owned from now on (lanes list ignores in their reply instead).
- amend: Bend 2 = compiled strict affine language (NOT HVM; fork-join runtime, no work stealing), U32 only (wrapping, no mul-hi) + 48-bit Nat → 16×16-bit limbs, R=2^256; Metal works on the mini; CUDA via NVRTC (sm_120 iff NVRTC accepts). Frozen bend2/FORMAT.md (Montgomery-form LE u32 words, CSR r1cs). Wave 1 Bend = field+curve single shard (sequential dependency) ‖ exporter.
- skip: w1conv review — exporter ships verify_bin.py round-trip (0 mismatches K=4..18 + vectors); Bend field tests exercise the same bytes.
- skip: w0f review — probe shard; montmul claims re-validated by w1field tests vs arkworks vectors.
- skip: w0a review — doc-only shard, orchestrator read sections 1–4; corrections folded by w0f if any.

## Verification matrix
| id | wave | command/probe | expected | verifier | keep/kill | evidence |
|---|---|---|---|---|---|---|
| V0.1 | 0 | bend run-c bend/probe/numeric.bend | rows of docs/bend-probe.md §2 | astra 401804b1 | keep | all rows match |
| V0.2 | 0 | gen-c + clang TPC_L2=0 vs 3 parallel.bend | ~5× MIPS | astra | keep | 174.8→896.2 MIPS |
| V0.3 | 0 | compiled limbmul.bend 3 runs | identical checksum | astra | kill | 1/3 garbage x1fffffff → HVM2 runtime instability (report ceiling) |
| V0.4 | 0 | io.bend byte decode | 0x80 → 128 | astra | kill | signed-char bug in probe; documented, timing unaffected |
| V0.5 | 0 | embed 2^20 literals | fails | astra | keep | HVM output had no result |
| V0.6 | 0 | groth16-ref verify proof_ref K=4..18 / tampered | OK / INVALID | fable 2b106e2c | keep | verify test added |
| V0.7 | 0 | gnark constraint count == N, proofs verify | true | fable ebecad7b | keep | |

## Key numbers so far (M4, 10 cores)
- arkworks prove 2^10/14/18/20: 17 / 142 / 1791 / 12762(load 17!) ms under sibling load; MSM G1 2^18 186 ms, 2^20 703 ms. ALL mini CPU numbers must be re-run on a quiet host in a final bench wave (arkworks, gnark, rapidsnark, snarkjs, Bend) — record loadavg.
- gnark prove 2^10/14/18/20 (10 thr): 13.4 / 97 / 928 / 3929 ms; 1 thr 2^14 1845 ms; MSM G1 2^20 848 ms (10 thr); FFT 2^20 43 ms.
- rapidsnark (10 thr) 2^10/14/18/20: 20.8 / 151 / 2723 / 9792 ms; snarkjs 402 / 1419 / 18425 / 59408 ms (under load; zkey load included in wall). circom constraint counts exact.
- Bend 2 (2.0.5): montmul 2^24 batch 1914 ms 1-thr (8.8 M/s), 440 ms 10-thr (38 M/s), Metal 78 ms (~200 M/s; chained ~670 M/s). Arrays 2^24 gather 62 ms; 8 MB file→Array 30 ms. No argv; Nat literal ≥10000n crashes checker; Metal call overhead ~55 ms.
- Bend 1/HVM2: u24 only, 12-bit limbs ×22; 254-bit schoolbook mul ≈ 51k interactions; 2^16 muls = 4.98 s on 8 thr compiled (~13k muls/s; ~2.7k 1-thr). Tree reduce scales 5.1× on 8 thr; loops 0×. Embedded literals cap 2^16 (compiled)/2^18 (interp); IO/FS/read_file works (~1 s per 2^18 limbs). Heap prealloc 6.4 GB RSS per compiled process.

## Residuals
(none)

## Playbook
plan waves → spec wave → build → review → integrate → verify → fix(≤2) → amend → … → final review → merge main → report. Skips logged as `skip: <reason>`.
