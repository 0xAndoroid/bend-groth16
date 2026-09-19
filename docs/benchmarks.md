# Benchmarks — Bend 2 Groth16 prover vs. production provers

**Verdict:** the Bend 2 prover is correct (every run verifies with arkworks and is bit-identical to the reference
proof) and not competitive: 40× slower than gnark at 2^18 on a 10-core M4 (both on 10 threads), 173–184× at
2^18–2^20 on a 48-thread Threadripper; its own GPU path is slower than its CPU path (Metal 7.5×, CUDA 1.8×) and
sits ~1,000–1,800× behind gnark+ICICLE / ICICLE-SNARK on the same RTX 5090 at 2^20. Raw Bend device arithmetic
is fast (2^30 `Fr.mul` at 15 G/s, 2^26 mixed G1 adds at 1.0 G/s on CUDA — 104–110× the 48-thread CPU); the prover
loses on *shape*: single-owner arrays (every split/join copies), host-driven fork-join with fixed placement, private
per-leaf bucket sets, U32-only limbs. Details: `docs/used-properly-audit.md`, `bend2/bench/prover_results.md`.

All numbers: SquareChain(2^K) over BN254 (K constraints, K+2 wires, one public scalar), median wall-clock ms.
Bend rows = the prover's own `T total` (includes key/witness loading; excludes compile, runtime start-up and the
external verify), MSM v2 defaults. Raw data: `bench/*.json`, `bench/quiet/*.json`; per-phase tables:
`bend2/bench/prover_results.md`; loaded-vs-quiet analysis: `bench/quiet-results.md`.

## Headline ratios (Bend 2 ÷ comparator)

| Comparison | 2^10 | 2^14 | 2^18 | 2^20 |
|---|---|---|---|---|
| Mini · Bend CPU 10 threads ÷ gnark 10 threads | 77× | 86× | 40× | — |
| Mini · Bend Metal ÷ gnark 10 threads | 1,633× | 505× | 300× | — |
| Box · Bend CPU 48 threads ÷ gnark 47 threads | 240× | 197× | 184× | 173× |
| Box · Bend CUDA ÷ gnark+ICICLE | 169× | 367× | 1,160× | 1,020× |
| Box · Bend CUDA ÷ ICICLE-SNARK | 227× | 537× | 1,360× | 1,813× |
| Box · Bend CUDA ÷ Bend CPU 48 threads | 5.2× | 3.1× | 1.6× | 1.8× |

Bend was not run at 2^20 on the 16 GB mini (the K=20 export is 2.3 GB).

## Full prover — Mac mini (Apple M4, 10 cores, 16 GB, Metal)

Comparator and Bend CPU columns from the quiet rerun (strictly sequential, load1 ≤ 4 at process start,
`bench/quiet/`); Bend Metal from the first pass (load1 2–3).

| K | Bend CPU1 | Bend CPU10 | Bend Metal | arkworks 0.5 full | arkworks matrices | gnark 10 threads | gnark 1 thread | rapidsnark CLI | snarkjs CLI |
|---|---|---|---|---|---|---|---|---|---|
| 2^10 | 846 | 629 | 13,389 | 17.6 | 17.2 | 8.2 | 45.1 | 16.8 | 255 |
| 2^14 | 11,456 | 6,000 | 35,048 | 139.3 | 123.8 | 69.4 | 416.9 | 104.0 | 935 |
| 2^18 | ≈125,000 † | 31,836 | 239,536 ‡ | 1,669.6 | 1,512.6 | 799.5 | — | 1,351.0 | 9,120 |
| 2^20 | — | — | — | 6,573.0 | 6,030.1 | 2,952.7 | — | 5,011.0 | 36,000 |

† estimate: measured only with MSM v1 (97,707 ms), scaled by the v1→v2 ratio at 2^14 (1.30×).
‡ needs `--gpu 8GB` (default arena span: `bend: out of memory`).

## Full prover — CUDA box (Threadripper 9960X 24C/48T, RTX 5090, 125 GiB)

| K | Bend CPU1 | Bend CPU48 | Bend CUDA | gnark 47 threads | gnark 1 thread | rapidsnark CLI | snarkjs CLI | gnark+ICICLE | same, PK pinned | ICICLE-SNARK |
|---|---|---|---|---|---|---|---|---|---|---|
| 2^10 | 1,213 | 860 | 4,484 | 3.6 | 35.3 | 22.0 | 373 | 26.5 | 26.1 | 19.7 |
| 2^14 | 16,284 | 3,728 | 11,461 | 19.0 | 321.2 | 60.5 | 669 | 31.2 | 30.1 | 21.3 |
| 2^18 | — | 34,906 | 56,083 | 189.4 | — | 643.9 | 2,894 | 48.3 | 44.4 | 41.3 |
| 2^20 | — | 115,004 | 207,286 | 665.7 | — | 2,030.5 | 10,663 | 203.2 | 180.6 | 114.3 |

Bend CUDA = `BENDG_GPU=1 --gpu 16GB`, peak `memory.used` 21,257 MiB at 2^20. gnark+ICICLE is slower than gnark
CPU below 2^18 (≈26 ms floor incl. launch, transfers and solver). ICICLE-SNARK excludes zkey parsing (cached on
device) and witness solving. No arkworks run on the box.

## Where the Bend prover spends its time

Phase medians (ms) from the prover's `T` lines; MSM is 93–99 % of every run and the single G2 MSM (`msm_b2`)
37–53 %. Loading + evaluation + QAP is 5 % (box) / 7 % (mini).

| K · config | load | evals | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l | total |
|---|---|---|---|---|---|---|---|---|---|
| Mini 2^18 CPU 10 threads | 734 | 163 | 1,342 | 4,082 | 4,176 | 13,808 | 5,919 | 3,261 | 33,491 |
| Mini 2^18 Metal | 771 | 162 | 2,478 | 27,647 | 27,869 | 116,589 | 41,630 | 22,386 | 239,536 |
| Box 2^20 CPU 48 threads | 3,502 | 926 | 2,665 | 15,458 | 15,385 | 51,602 | 16,476 | 8,980 | 115,003 |
| Box 2^20 CUDA | 3,898 | 984 | 8,583 | 32,282 | 33,003 | 77,240 | 32,690 | 18,598 | 207,286 |

Threads help the NTTs far more than the MSMs: 1 → 10 threads at 2^14 gives 2.1× on the whole prover (`msm_b2`
1.8×, `qap` 4.6×); 1 → 48 threads on the box 4.4× (`msm_b2` 3.8×, `qap` 8.5×).

## Primitives

MSM v1 = window c 8 (12 from 2^18), fork depth min(4, log2 n − c) → 16 leaves. MSM v2 (current default) = c 8
(10 from 2^20), depth min(7, log2 n − c − 1) → 128 leaves. Checksums equal across thread counts and backends.

### Fr multiplication throughput (M mul/s)

| Implementation | Mini 1 thread | Mini 10 threads | Mini Metal | Box 1 thread | Box 48 threads | Box CUDA |
|---|---|---|---|---|---|---|
| Bend 2 `Fr.mul` batch | 9.2 | 48 | 230 | 6.2 | 128 | 15,100 (2^30 in 71 ms) |
| arkworks 0.5 (independent / dependent) | 106 / 96 | — | — | — | — | — |
| gnark-crypto 0.21 (independent / dependent) | 119 / 73 | — | — | — | — | — |

Single-thread Bend is 8–13× behind Rust/Go: the 16 × 16-bit CIOS with U32-only arithmetic is the cost.

### G1 `add_mixed` throughput (M add/s; 2^20 chains, box CUDA 2^26)

| Mini 1 thread | Mini 10 threads | Mini Metal | Box 1 thread | Box 48 threads | Box CUDA |
|---|---|---|---|---|---|
| 0.67 | 3.5 | 10.6 | 0.46 | 7.8 | 1,030 (65 ms) |

### MSM G1 — Mac mini (ms)

| n | Bend v1 CPU1 | Bend v1 CPU10 | Bend v1 Metal | Bend v2 CPU10 | Bend v2 Metal | arkworks 10 threads | gnark 10 threads | gnark 1 thread |
|---|---|---|---|---|---|---|---|---|
| 2^10 | 117 | 94 | 1,384 | — | — | 1.58 | 1.09 | 5.9 |
| 2^12 | 412 | 348 | 2,722 | — | — | 4.44 | 3.46 | 19.2 |
| 2^14 | 1,835 | 604 | 8,502 (c=10) | — | — | 14.5 | 9.91 | 55.7 |
| 2^16 | 4,783 | 1,896 | 28,327 (c=12) | 1,096 | 9,711 | 49.5 | 34.4 | 183 |
| 2^18 | 14,819 | 6,547 | 43,349 | 3,160 | 14,909 | 171 | 115 | 611 |
| 2^20 | 41,514 | 20,808 | 106,468 | 10,302 | — | 641 | 391 | 2,167 |

v2 CPU10, arkworks and gnark columns: quiet rerun. v1 and v2 Metal rows: `bend2/bench/msm_results.md` (measured
before the bench-loader fix — timing unaffected, checksums not comparable). Bend v2 ÷ gnark at 2^20 = 26×.

### MSM G1 — box (ms)

| n | Bend v2 CPU1 | Bend v2 CPU48 | Bend v2 CUDA | Bend v1 CPU48 | Bend v1 CUDA | ICICLE v4 device-resident | ICICLE v4 host scalars | sppark 0.1.15 (H2D incl.) |
|---|---|---|---|---|---|---|---|---|
| 2^10 | 191 | 199 | 2,006 | 96 | 466 | 2.28 | 2.91 | 1.91 |
| 2^12 | 547 | 182 | 2,025 | 160 | 928 | 2.61 | 3.17 | 2.05 |
| 2^14 | 1,958 | 376 | 2,502 | 292 | 1,397 | 2.84 | 3.68 | 3.04 |
| 2^16 | 7,612 | 1,104 | 2,978 | 780 | 2,109 | 2.78 | 3.80 | 7.91 |
| 2^18 | — | 2,942 | 4,273 * | 3,169 | 16,989 | 3.55 | 4.83 | 24.7 |
| 2^20 | — | 9,521 | 17,075 * | 8,577 | 29,341 | 7.17 | 7.39 | 92.0 |

\* single run; CUDA rows show the best fork depth of the sweep (`bend2/bench/box_results.md`). ICICLE
device-resident = kernel only; sppark copies points and scalars on every call. Bend v2 CUDA ÷ ICICLE at 2^20 = 2,381×.

### NTT — forward FFT over Fr (ms)

| n | Mini Bend CPU1 | Mini Bend CPU10 | Mini Bend Metal | Mini arkworks 10 threads | Mini gnark 10 threads | Box Bend CPU1 | Box Bend CPU48 | Box Bend CUDA | ICICLE device | ICICLE host | sppark host |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2^10 | 3 | 3 | 62 | 0.18 | 0.040 | 6 | 7 | 12 | 0.025 | 0.19 | 0.029 |
| 2^12 | 11 | 7 | 75 | 0.48 | 0.11 | 14 | 13 | 21 | 0.025 | 0.14 | 0.038 |
| 2^14 | 32 | 15 | 114 | 0.98 | 0.33 | 41 | 20 | 47 | 0.030 | 0.19 | 0.093 |
| 2^16 | 135 | 26 | 392 | 2.84 | 1.22 | 146 | 48 | 142 | 0.055 | 0.32 | 0.22 |
| 2^18 | 566 | 95 | 1,123 | 10.1 | 5.09 | — | 168 | 517 | 0.140 | 0.74 | 0.69 |
| 2^20 | 1,987 | 389 | 3,381 | 40.7 | 22.4 | — | 423 | 3,133 | 0.622 | 2.96 | 2.63 |

Mini Bend CPU10 ÷ gnark at 2^20 = 17×. Metal is 6–21× slower than 10 CPU threads for a single transform and wins
only on the 7-transform `qap_h` at 2^19 (2,220 vs 2,646 ms) where three pipelines overlap.

## Bend 2 ceilings hit

| Ceiling | Consequence |
|---|---|
| U32 only, no mul-hi / U64 | 16 × 16-bit limbs; `Fr.mul` 9.2 M/s single-thread vs ~100 M/s in Rust/Go |
| Single-owner arrays; split = copy ([bendlang/bend#804](https://github.com/bendlang/bend/issues/804)) | no shared point table for MSM; private per-leaf buckets (1 GiB G1 at 2^20); every split copies both halves |
| Fixed placement, no work stealing | leaf count must be ≥ ~128 to balance 10 cores; v1's 16 leaves scaled 2× on 10 threads |
| ~55 ms per Metal `!`, host-driven grow/work/pack rounds | six entries per proof ≈ 330 ms fixed; small transforms 20× slower on Metal than CPU |
| Metal default span 2 GB | `--gpu 8GB` needed at K=18; c=12, d=8 OOM at 8 GB |
| `Nat` is a 48-bit word; literal ≥ 10000n crashes the checker (#791, #779) | counters via `Nat.pow`; no `Nat` in arithmetic |
| No argv; input via `IO.get_env` + `File.read_bytes` byte lists | loader packs bytes one by one: 0.7 s (mini) / 3.5 s (box K=20) |
| CUDA needs clang ≥ 19; NVRTC JIT | stock Ubuntu clang 18 rejected; apt.llvm.org clang-19 works |

## Comparators

| Prover | Pin | Role |
|---|---|---|
| gnark + gnark-crypto | v0.16.3 / v0.21.0 | CPU state-of-the-art baseline (production: Celer, Linea, Brevis) |
| rapidsnark | v0.0.8 (mini: 81eddf1) | CPU production, Circom stack |
| snarkjs | 0.7.6 | reference only |
| arkworks ark-groth16 | 0.5 | reference; data source and verifier |
| gnark + icicle-gnark | v3.2.2 | GPU production family (experimental upstream integration) |
| ICICLE-SNARK | bf00385 | GPU, experimental |
| ICICLE v4 / sppark | open-icicle v4.0.0 / v0.1.15 | GPU primitive ceilings (BN254 MSM/NTT only) |

Timer-boundary caveats (what each number includes) are listed in `docs/review-findings-2026-09.md`; the
selection rationale is in `docs/comparators.md`.

## Hardware and toolchain

- **Mac mini:** Apple M4, 10 cores (4P+6E), 16 GB, Metal; macOS; Bend 2.0.5, Go 1.27.1, Rust stable, Node 26.
- **CUDA box:** AMD Ryzen Threadripper 9960X 24C/48T, 125 GiB, NVIDIA RTX 5090 32 GB (sm_120), driver 595.84,
  CUDA 12.8, clang 19.1.7, Ubuntu 24.04 — `docs/box.md`.

## How to reproduce

```sh
# data (arkworks): pk / vk / witness / reference proof, then export to the Bend binary format
cargo run --release --manifest-path ref/Cargo.toml -- gen --log2 K --out data/K
uv run python bend2/tools/export_bin.py data/K
# Bend prover, CPU (all threads / one thread) and GPU
sh bend2/scripts/prove.sh K
sh bend2/scripts/prove.sh K --threads 1
BENDG_GPU=1 sh bend2/scripts/prove.sh K            # Metal; add --gpu 16GB on CUDA
# JSON rows for bench/bend2-*.json
sh bend2/scripts/bench_prover.sh run cpu_all 3 K
# primitives
BEND_NO_TELEMETRY=1 ~/.bend/bin/bend bend2/bench/msm.bend -o msm && MODE=cpu G=1 N=18 ./msm
BEND_NO_TELEMETRY=1 ~/.bend/bin/bend bend2/bench/ntt.bend -o ntt && OP=fft N=20 ./ntt
# comparators
cargo run --release --manifest-path ref/Cargo.toml -- bench --log2 K     # arkworks
(cd comparators/gnark && go build -o gnark-bench . && ./gnark-bench prove --log2 K)  # gnark
comparators/circom/README.md                                               # rapidsnark / snarkjs on the mini
docs/box.md                                                                # CUDA box: gnark+ICICLE, ICICLE-SNARK, ICICLE/sppark
```

Run one benchmark process at a time; every JSON row records the 1-minute load average and the loaded-vs-quiet
comparison in `bench/quiet-results.md` shows why (10-thread comparator numbers inflate 1.3–2.8× under load).
