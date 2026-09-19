# bend-groth16

A Groth16 prover over BN254 written in [Bend 2](https://bend-lang.com) (2.0.5), built as a stress test of the
language and its runtime on a real cryptographic workload: 254-bit field arithmetic on U32 limbs, Pippenger MSMs
over G1/G2, radix-2 NTTs, a few hundred MB of proving key — on CPU threads, Metal and CUDA. Every proof is verified
with arkworks and compared bit-for-bit to the arkworks proof of the same instance. The same circuit is benchmarked
against gnark, rapidsnark, snarkjs, arkworks (CPU) and gnark+ICICLE, ICICLE-SNARK, ICICLE/sppark primitives (RTX 5090).

**Result:** correct, not competitive — 40× slower than gnark at 2^18 constraints on a 10-core M4, 173–184× on a
48-thread Threadripper, and the `!` GPU path is slower than the CPU path (Metal 7.5×, CUDA 1.8×). Raw device
arithmetic is fast (2^30 `Fr.mul` at 15 G/s on CUDA); the prover loses on data shape — single-owner arrays,
host-driven fork-join, private per-leaf buckets. Full tables: [docs/benchmarks.md](docs/benchmarks.md).

## Layout

- `bend2/` — the prover: `src/` (`fr`, `fq`, `fq2`, `g1`, `g2`, `msm`, `ntt`, `groth16`, `bin_io`), `prove.bend`
  (entry), `tests/`, `bench/` (primitive benches + `*_results.md`), `scripts/` (`prove.sh`, `bench_prover.sh`),
  `tools/` (JSON ↔ `.bin` export, proof conversion), `gen/` (field/curve/msm/ntt generators), `FORMAT.md`, `README.md`
- `ref/` — arkworks reference harness (Rust): circuit, pk/vk/witness export, verifier, CPU baselines
- `comparators/` — gnark, circom (rapidsnark/snarkjs), gpu (ICICLE, sppark), box (CUDA-box recipes)
- `bench/` — results as JSON (schema in `bench/README.md`); `bench/quiet/` = quiet-host rerun
- `bend/` — Bend 1 / HVM2 probes (superseded by `bend2/`; kept for the Bend 1 vs Bend 2 comparison)
- `docs/` — see below

## Run

Requires Bend 2.0.5 (`curl -fsSL https://bend-lang.com/install.sh | BEND_NO_TELEMETRY=1 sh`; the prover calls
`~/.bend/bin/bend` explicitly), Rust (for `ref/`), `uv` (stdlib-only Python tools). Data lives in
`data/<K>/bend/*.bin` (gitignored) and is produced by the arkworks harness:

```sh
git clone https://github.com/0xAndoroid/bend-groth16 && cd bend-groth16
cargo run --release --manifest-path ref/Cargo.toml -- gen --log2 10 --out data/10   # pk, vk, witness, reference proof
uv run python bend2/tools/export_bin.py data/10                                       # → data/10/bend/*.bin (bend2/FORMAT.md)

sh bend2/scripts/prove.sh 10                 # build, prove, verify with arkworks (OK), compare to proof_ref (EQUAL)
sh bend2/scripts/prove.sh 10 --threads 1     # single thread
BENDG_GPU=1 sh bend2/scripts/prove.sh 10     # Metal / CUDA `!` dispatch for the five MSMs and the QAP NTTs
sh bend2/tests/run.sh                        # every bend2 test, ends with the K=4 prove (OK + EQUAL)
```

The prover prints `A x y`, `B x0 x1 y0 y1`, `C x y`, then `T <phase> <ms>` lines
(`load evals qap msm_a msm_b1 msm_b2 msm_h msm_l total`). K=18 needs `--gpu 8GB` (arena span), K=20 about 20 GB.

## What we measured

SquareChain(2^K) — K squaring constraints, K+2 wires, one public output — at K = 10, 14, 18, 20; median ms.

| | 2^10 | 2^14 | 2^18 | 2^20 |
|---|---|---|---|---|
| Bend 2, M4 10 threads | 629 | 6,000 | 31,836 | — |
| gnark, M4 10 threads | 8.2 | 69.4 | 800 | 2,953 |
| Bend 2, Threadripper 48 threads | 860 | 3,728 | 34,906 | 115,004 |
| Bend 2, RTX 5090 (`!`) | 4,484 | 11,461 | 56,083 | 207,286 |
| gnark + ICICLE, RTX 5090 | 26.5 | 31.2 | 48.3 | 203 |

MSM is 93–99 % of every Bend run; the single G2 MSM alone is 37–53 %. All numbers, primitives (MSM, NTT, `Fr.mul`,
G1 add), phase breakdowns, hardware and reproduction steps: [docs/benchmarks.md](docs/benchmarks.md).

## Bend usage notes

- [docs/bend2-idioms.md](docs/bend2-idioms.md) — language and runtime facts learned while writing this (U32-only
  arithmetic, single-owner arrays, `!` fork-join, Metal/CUDA dispatch cost, arena spans, `Nat` limits, IO).
- [docs/used-properly-audit.md](docs/used-properly-audit.md) — is the prover written the way a Bend 2 expert would
  write it? Verdict PARTIAL, with the module-by-module checklist and what would be done differently.
- [docs/review-findings-2026-09.md](docs/review-findings-2026-09.md) — independent review: timer boundaries,
  apples-to-oranges caveats, stale-doc list.
- [bend2/README.md](bend2/README.md), [bend2/FORMAT.md](bend2/FORMAT.md) — module layout, binary interchange format.
- Bend 1 / HVM2: [docs/bend-idioms.md](docs/bend-idioms.md), [docs/bend-probe.md](docs/bend-probe.md).

## Open questions for the Bend team

Collected in [docs/review-notes.md](docs/review-notes.md) (language/runtime questions raised by the prover:
shared read-only buffers, zero-copy views, widened integer products, device-resident scheduling, work stealing)
and [docs/formal-verification.md](docs/formal-verification.md) (what Bend 2's type system could check about this
code). Issues we hit: [bendlang/bend#804](https://github.com/bendlang/bend/issues/804) (array split copies),
#791 / #779 (`Nat` literals ≥ 10000n crash the checker).

## License

MIT — see [LICENSE](LICENSE).
