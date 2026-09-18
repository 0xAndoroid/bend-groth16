# bend-groth16

Benchmark subject: a Groth16 prover over BN254 written in [Bend 2](https://bend-lang.com) (2.0.5, `bend2/`),
compared against arkworks, gnark, rapidsnark, snarkjs (CPU) and gnark+ICICLE, ICICLE-SNARK, ICICLE/sppark
primitives (GPU, one rented CUDA box). Groth16 is only the benchmark subject here.

Report: [Bend 2 Groth16 benchmark (Sep 2026)](https://me.andrew.ee/reports/bend-groth16-bench-2026-09.html) — verdict, full-prover and primitive tables, audit, ceilings.

Layout:
- `bend2/` — the prover: `src/` (fr, fq, fq2, g1, g2, msm, ntt, groth16, bin_io), `prove.bend` (entry),
  `tests/`, `bench/` (primitive benches + `*_results.md`), `scripts/` (`prove.sh`, `bench_prover.sh`),
  `tools/` (JSON ↔ `.bin` export, proof conversion), `gen/` (field/curve/msm/ntt generators), `FORMAT.md`
- `bend/` — Bend 1 / HVM2 legacy probes (superseded by `bend2/`)
- `ref/` — arkworks reference harness (Rust): circuit, pk/vk/witness export, verifier, CPU baselines
- `comparators/` — gnark, circom (rapidsnark/snarkjs), gpu (ICICLE, sppark), box (rented-box recipes)
- `bench/` — benchmark results as JSON (`bend2-macmini.json`, `bend2-box.json`, `gnark-*.json`, `box-*.json`, …), schema in `bench/README.md`
- `docs/` — `bend2-idioms.md` (language facts), `used-properly-audit.md` (is Bend used properly? verdict PARTIAL),
  `box.md` (CUDA box snapshot), `comparators.md` (research plan)
- `.journals/` — campaign journal

Prove and test (data lives in `data/<K>/bend/*.bin`, gitignored; produced by `ref/` + `bend2/tools/export_bin.py`):

```sh
sh bend2/scripts/prove.sh K [--threads 1]      # build, prove data/K, verify with arkworks, compare to proof_ref
BENDG_GPU=1 sh bend2/scripts/prove.sh K        # Metal / CUDA dispatch for the five MSMs and the QAP NTTs
sh bend2/tests/run.sh                          # every bend2 test, ends with the K=4 prove (OK + EQUAL)
```

The prover prints `A x y`, `B x0 x1 y0 y1`, `C x y`, then `T <phase> <ms>` lines (`load evals qap msm_a msm_b1
msm_b2 msm_h msm_l total`).

Results: `bend2/bench/prover_results.md` (full prover, mini + box), `bend2/bench/msm_results.md`,
`bend2/bench/ntt_results.md` (primitives), `bench/*.json` (all frameworks, raw), `docs/used-properly-audit.md`.
