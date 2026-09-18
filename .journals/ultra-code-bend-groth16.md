# ultra-code · bend-groth16 (orchestrator task 72b51735, kanban #466)

Started 2026-09-18 01:22 ET. Owner reads result in the morning. Report: ~/.pika/web/reports/bend-groth16-bench-2026-09.html

## Rules (verbatim in every lane prompt)
- All code lanes Fable; verifiers/reviewers mixed Fable + gpt-6-astra. Lane names `bend-groth16 · <step> <i>/<n>`; sleeps carry `--reason "<step> i/n"`.
- Dev only under ~/dev; scratch under $TMPDIR; no bare rm (`rip`). Mini: ≤3 concurrent Rust-building lanes. Never `pkill -f`/`killall`.
- Vast.ai: label MUST start with `pika`; price < $5/h; image ghcr.io/0xandoroid/pika-vast:latest with `--login "-u 0xAndoroid -p $GITHUB_TOKEN ghcr.io"` + `--onstart-cmd /opt/pika/onstart.sh`; ONE box only; destroy with `echo y | vastai destroy instance <id>` and VERIFY gone; never touch non-pika instances. Budget ≤$40.
- Groth16 here is a benchmark subject only; nothing touches Jolt.
- Teardown at the end: no leftover processes, box destroyed, worktrees removed.

## Frozen decisions
- Wave-2 Bend interfaces: `Msm.g1/g2(points, scalars_canonical, n) -> pts & (scs & G)`, `Ntt.fft/ifft/coset_fft/coset_ifft(a, log2)`, `Ntt.qap_h(a,b,c,log2)` (libsnark reduction), arrays 16/32/64 words per element; prover imports `./naive.bend as Msm/Ntt` to be flipped to `./msm.bend`/`./ntt.bend` at integration.
- Curve BN254 (Fr scalar field, Fq base field). Canonical circuit `SquareChain(N)`: private x0; x_{i+1} = x_i * x_i for i<N; x_N public output. Exactly N constraints. Same circuit in every framework (arkworks, circom, gnark, bellperson).
- Sizes: full prover 2^10, 2^14, 2^18 (+2^20 for comparators if cheap). Primitives: MSM 2^10..2^20, NTT 2^10..2^20, field mul throughput.
- Data exchange format (arkworks exports, Bend consumes): `data/<log2N>/{r1cs,witness,pk,vk,proof_ref,public}.json` — hex 0x big-endian field elements, G1 `{x,y}` affine, G2 `{x:[c0,c1],y:[c0,c1]}`, infinity `{"inf":true}`. Test vectors `data/vectors/{fr_ops,fq_ops,g1_ops,g2_ops,msm_small,ntt_small}.json`. `ref verify --vk --proof --public` exit 0/1.
- Comparators (owner, 01:25): production CPU SOTA — gnark, rapidsnark, bellperson; arkworks correctness+1 CPU point; snarkjs reference only; GPU ICICLE (+ sppark if cheap) vs Bend-CUDA. Research lane confirms 2026 state.

## Wave table
| wave | shards | depends on | status |
|---|---|---|---|
| 0 | A bend-research fca3d86a (astra) · B bend-probe 9b7f93c3 (fable) · C arkworks-ref 4618ccc0 (fable) · D prover-research 150cad70 (astra) · E circom-rapidsnark e4be3580 (fable) · F bend2-probe 454fe86d (fable) · review C 2b106e2c · review B 401804b1 (astra) | — | building (all integrated) |
| 1 | gnark-mini 8e7167e8 (fable) · gpu-box 6b6fc33c (integrated; box 51392026 pika-bend-5090 $0.628/h, running) · [after w0f] bend2-field-curve 41379b12 (integrated; tests PASS 64/64/32/16; review e6516c76 astra) · bend2-export 53ed8004 (integrated; K=18 export 4.3 s, 308 MB, 0 round-trip mismatches) · review gnark ebecad7b | 0 | gnark integrated; box + bend2 lanes building |
| 2 | bend2-msm 3492204e (integrated; review d95f6611 astra) · bend2-ntt 876e5746 (integrated; reviewed 3052ee89 keep) · bend2-prover a581bb4c (integrated: K=4 + K=10 naive OK+EQUAL; G2Aff.to_array bug fixed on integration by orchestrator) | 1 | msm/ntt building |
| 3 | bend2-cuda-smoke 20d69844 (integrated) · prover imports flipped by orchestrator (K=4 115 ms, K=10 1103 ms OK+EQUAL) · bend2-prover-bench b3ef68f2 (mini + box full prover, box msm/ntt CUDA) · bend2-msm-opt 6654ff4c (60-min time-box, v2 MSM) | 2 | building |
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
| V1.1 | 1 | bend2/tests/run.sh + corrupted vector | PASS 64/64/32/16; FAIL on corruption | astra e6516c76 | keep | FAIL 5 mul on flipped word |
| V1.2 | 1 | 3 random Fr products, inv(0), sub borrow; G1 edge cases | match bigint / 8/8 | astra | keep | |
| V1.3 | 1 | README bench numbers ±30% | within | astra | kill (minor) | Fr20 Metal +63%, Fr24 CPU10 +31% — single samples under sibling load; quiet rerun wave re-measures |
| V1.4 | 1 | benchmark does real work (generated C inspected) | yes | astra | keep | |
| V1.5 | 1 | used-properly checklist (field layer) | all P | astra | keep | 9/9 applicable P |
| V2.1 | 2 | test_ntt vectors + qap_h K=4/10 vs ref_qap; corrupt → FAIL | PASS / FAIL | astra 3052ee89 | keep (FAIL exits 0 — minor) | |
| V2.2 | 2 | ref_qap oracle: A·B−C = h·Z_d at 3 random points, independent bigint | residual 0 | astra | keep | ark-groth16 r1cs_to_qap.rs:176 confirms instance rows |
| V2.3 | 2 | ntt bench ±30%, checksums CPU=Metal | within | astra | keep | |
| V2.4 | 2 | ntt used-properly | all P | astra | partial | 7 pass, 2 partial, #5 fail (array split copies O(n·FD)) |
| V2.5 | 2 | prover K=4/K=10 real modules OK+EQUAL | OK EQUAL | orchestrator | keep | 115 ms / 1103 ms |
| V2.6 | 2 | test_msm PASS 3/3 + naive oracle n=5/3000/4096 | equal | astra d95f6611 | keep | |
| V2.7 | 2 | test_msm FAIL exits non-zero | non-zero | astra | kill | exit 0 → fixer |
| V2.8 | 2 | msm bench ±30% | within | astra | kill (minor) | 2^16 10-thr +51% (load); checksums equal |
| V2.9 | 2 | "MSM ceiling is the language" | — | astra | kill | g1_add FD=4 scales 1.98× too, FD=14 halves time → v1 flat scaling = fd=4 choice, not runtime. Passed to msm-opt lane. |

## Key numbers so far (M4, 10 cores)
- arkworks prove 2^10/14/18/20: 17 / 142 / 1791 / 12762(load 17!) ms under sibling load; MSM G1 2^18 186 ms, 2^20 703 ms. ALL mini CPU numbers must be re-run on a quiet host in a final bench wave (arkworks, gnark, rapidsnark, snarkjs, Bend) — record loadavg.
- gnark prove 2^10/14/18/20 (10 thr): 13.4 / 97 / 928 / 3929 ms; 1 thr 2^14 1845 ms; MSM G1 2^20 848 ms (10 thr); FFT 2^20 43 ms.
- rapidsnark (10 thr) 2^10/14/18/20: 20.8 / 151 / 2723 / 9792 ms; snarkjs 402 / 1419 / 18425 / 59408 ms (under load; zkey load included in wall). circom constraint counts exact.
- Bend 2 (2.0.5): montmul 2^24 batch 1914 ms 1-thr (8.8 M/s), 440 ms 10-thr (38 M/s), Metal 78 ms (~200 M/s; chained ~670 M/s). Arrays 2^24 gather 62 ms; 8 MB file→Array 30 ms. No argv; Nat literal ≥10000n crashes checker; Metal call overhead ~55 ms.
- BOX (Threadripper 9960X 24C/48T + RTX 5090, $0.628/h): gnark CPU prove 2^10/14/18/20 = 3.6/19/189/666 ms (1 thr 2^14 321 ms); rapidsnark CLI cold 22/60/644/2031 ms; snarkjs 373/669/2894/10663 ms. GPU: gnark+icicle 26/31/48/203 ms (pinned 26/30/44/181); ICICLE-SNARK 20/21/41/114 ms. Primitives 5090: ICICLE MSM 2^20 7.17 ms (device-resident), sppark MSM 2^20 92 ms (incl H2D); ICICLE NTT 2^20 0.62 ms. Bend 2 CUDA target builds on box (clang-19 needed, NVRTC JIT).
- Bend 2 FULL PROVER (mini, 10 thr, real MSM/NTT): K=4 115 ms; K=10 1103 ms (msm_b2 481, msm_h 240, msm_l 141, msm_a 104, msm_b1 101, qap 17) vs gnark 13 ms / arkworks 17 ms / rapidsnark 21 ms → ~65–85× slower at K=10.
- Bend 2 MSM v1 (mini): G1 2^20 41.5 s / 20.8 s (1/10 thr; 2× scaling only), Metal 106 s; 2^18 14.8/6.5 s; G2 2^18 29.3 s (10 thr). gnark 2^20 848 ms → ~25× slower. Review: flat scaling is mostly the fd=4 implementation choice (g1_add FD=4 also 1.98×; FD=14 halves time); language constraints (single-owner arrays, split=copy, no shared read-only buffers, fixed placement) shape the design but the time split is unmeasured → msm-opt lane v2 will tell.
- Bend 2 NTT (mini): fft 2^20 1987/529/3381 ms (1 thr/10 thr/Metal — Metal SLOWER); 2^16 135/47/392; qap_h 2^19 8836/2646/2220 ms. gnark FFT 2^20 = 43 ms (10 thr) → Bend ~12× slower on CPU NTT.
- Bend 2 on BOX: CUDA works (NVRTC sm_120, clang-19). field_mul 2^28: CPU48 2098 ms (128 M/s) vs CUDA 19 ms (14 G/s); 2^30 CUDA 71 ms. g1_add 2^26: CPU48 6776 ms vs CUDA 65 ms (1.03 G adds/s); 2^20 CPU48 134 ms vs CUDA 4 ms. Checksums equal.
- Bend 2 field lane: Fr.mul 2^24 1829/352/73 ms (1 thr/10 thr/Metal) = 9.2/48/230 M/s; G1.add_mixed 2^20 1570/301/99 ms = 0.67/3.5/10.6 M/s.
- Bend 1/HVM2: u24 only, 12-bit limbs ×22; 254-bit schoolbook mul ≈ 51k interactions; 2^16 muls = 4.98 s on 8 thr compiled (~13k muls/s; ~2.7k 1-thr). Tree reduce scales 5.1× on 8 thr; loops 0×. Embedded literals cap 2^16 (compiled)/2^18 (interp); IO/FS/read_file works (~1 s per 2^18 limbs). Heap prealloc 6.4 GB RSS per compiled process.

## Residuals
- (open, minor) tests: run.sh omits NTT/MSM; test_msm FAIL exits 0; bench/msm.bend loader offset wraps (point0 = file tail); test_ntt FAIL exits 0. ntt.bend array split copies O(n·FD) (checklist #5). Dead defs in test_ntt/ntt. → final-review fixer.
- (open, minor) tests/run.sh prints PASS 0 on empty/zero-count vector files; gen_field.py `head1` dead helper; Fq bit helpers uncalled → final-review fixer.

## Playbook
plan waves → spec wave → build → review → integrate → verify → fix(≤2) → amend → … → final review → merge main → report. Skips logged as `skip: <reason>`.
