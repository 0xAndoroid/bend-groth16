# Quiet-host rerun of the Mac mini CPU numbers

Mac mini, Apple M4 (10 cores, 16 GB), 2026-09-18 04:37–05:10 ET, head `baab824`. Every earlier mini number was taken while other builds and benchmarks loaded the host (load1 9–20); this rerun is **strictly sequential** (one benchmark process at a time) with a gate that waits for load1 ≤ 4 before every run (60 s × ≤5 retries; no run was aborted, the gate waited once or twice after each heavy step because our own previous run inflates load1). Raw JSON: `bench/quiet/*.json` (same schemas as `bench/`). Wall-clock ms, **median**; `load1` = 1-min load average right before the run.

Notes on what is verified: gnark verifies every timed proof; rapidsnark/snarkjs `bench.py` verifies every timed proof with `snarkjs groth16 verify`; Bend `prove.sh` verifies every run with the arkworks harness and compares to `proof_ref` (all OK + EQUAL); **arkworks `groth16-ref bench` verifies only the untimed warm-up proof per size** (`ref/src/bench.rs:88`), the `iters` timed proofs are not individually verified.

## arkworks (ark-groth16 0.5.0, rayon 10 threads)

| K | full prove ms | matrices-only ms | samples (full) | load1 |
|---|---|---|---|---|
| 10 | 17.6 | 17.2 | 17.6, 17.7, 17.5 | 3.38 |
| 14 | 139 | 124 | 142, 136, 139 | 3.38 |
| 18 | 1670 | 1513 | 1662, 1699, 1670 | 6.39 |
| 20 | 6573 | 6030 | 6573, 6541 | 7.45 |

Primitives (10 threads, median of 3): G1 MSM 2^16 / 2^18 / 2^20 = 49.5 / 171 / 641 ms; FFT 2^16 / 2^18 / 2^20 = 2.8 / 10.1 / 40.7 ms; Fr mul 1 thread 96 M/s dependent, 106 M/s independent (load1 4.01).

## gnark (v0.16.3, gnark-crypto v0.21.0, Go 1.27.1)

| K | 10 thread ms | samples | load1 | 1 thread ms | samples | load1 |
|---|---|---|---|---|---|---|
| 10 | 8.2 | 8.0, 8.1, 8.5, 8.3, 8.2 | 2.22 | 45.1 | 45.3, 45.0, 45.3, 45.1, 45.0 | 3.41 |
| 14 | 69.4 | 70.5, 70.3, 69.4, 68.1, 68.6 | 2.22 | 417 | 417, 418, 417, 416, 416 | 3.45 |
| 18 | 800 | 759, 835, 800 | 5.68 | — | — | — |
| 20 | 2953 | 2953 | 9.45 | — | — | — |

Primitives (10 threads): G1 MSM 2^16 / 2^18 / 2^20 = 34.4 / 115 / 391 ms; FFT 2^16 / 2^18 / 2^20 = 1.2 / 5.1 / 22.4 ms (load1 3.34); Fr mul 1 thread 73 M/s dependent, 119 M/s independent.

## rapidsnark (10 threads) and snarkjs (node, web workers)

| K | rapidsnark ms | samples | snarkjs ms | samples |
|---|---|---|---|---|
| 10 | 16.8 | 33.5, 16.8, 15.5 | 255 | 256, 255, 252 |
| 14 | 104 | 109, 104, 103 | 935 | 936, 935, 933 |
| 18 | 1351 | 1422, 1351, 1351 | 9120 | 9115, 9120, 9249 |
| 20 | 5011 | 5250, 5011, 4990 | 36000 | 36000 |

load1 at start: rapidsnark 3.04 (one process for all K), snarkjs 2.76 (K ≤ 18) / 3.38 (K = 20). Wall time includes process start + zkey load (562 MB at K=20). Artefacts: the zkeys/witnesses generated for the first pass (`comparators/circom/`), reused.

## Bend 2 prover (bend2/prove.bend, Bend 2.0.5, MSM v2 defaults)

| K | config | ms | samples | load1 | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 10 threads | 629 | 629, 626, 659 | 3.91/3.75/3.14 | 13.0 | 84.0 | 85.0 | 263 | 100 | 74.0 |
| 10 | `--threads 1` | 846 | 846, 845, 846 | 2.97/2.96/3.30 | 26.0 | 102 | 102 | 324 | 182 | 100 |
| 14 | 10 threads | 6000 | 6000, 6207, 5502 | 3.17/3.74/4.56 | 102 | 795 | 799 | 2509 | 892 | 669 |
| 14 | 10 threads, `--gpu off` | 5569 | 5569 | 3.88 | 97.0 | 766 | 764 | 2418 | 813 | 648 |
| 14 | `--threads 1` | 11456 | 11442, 11466, 11456 | 2.98/3.36/3.39 | 390 | 1359 | 1348 | 4318 | 2638 | 1329 |
| 18 | 10 threads (`--gpu 8GB` span) | 31836 | 31585, 32087 | 2.61/5.12 | 1336 | 3968 | 3994 | 12604 | 5787 | 3205 |

All runs OK + EQUAL. `cpu_all` = `prove.sh` default with `BENDG_GPU` unset (no `!` calls); `cpu1` passes `--threads 1` (phase timings differ 1.35–2× from the 10-thread rows, so the flag took effect). **K=18 with the default arena span now dies with `bend: out of memory: run again with a bigger span, as in --gpu 8GB`** (2 attempts at this head; earlier `bench/bend2-macmini.json` K=18 cpu_all has `args: ""`), so the K=18 row was run with `--gpu 8GB` (span only — `BENDG_GPU` unset). `--gpu off` at K=14 (10 threads): 5569 ms, inside the 10-thread spread (5502–6207), i.e. the GPU-backed default arena costs nothing measurable on the CPU path.

MSM G1 (`bench/msm.bend`, `MODE=cpu G=1`, v2 defaults, `--gpu 8GB` span, 10 threads, median of 3) and NTT fft (`bench/ntt.bend`, `OP=0`, default FD, 10 threads, median of 3):

| size | MSM G1 ms (c, fd) | samples | load1 | FFT ms | samples |
|---|---|---|---|---|---|
| 2^16 | 1096 (c=8, fd=7) | 1102, 1094, 1096 | 3.15/3.15/3.15 | 26 | 32, 26, 26 |
| 2^17 | — | — | — | 51 | 51, 52, 50 |
| 2^18 | 3160 (c=8, fd=7) | 3130, 3160, 3203 | 3.15/3.54/4.13 | 95 | 95, 97, 93 |
| 2^19 | — | — | — | 182 | 182, 182, 182 |
| 2^20 | 10302 (c=10, fd=7) | 10167, 10302, 10467 | 2.81/4.06/4.27 | 389 | 389, 390, 389 |

Affine results / checksums identical across the 3 runs of every size.

## Loaded vs quiet

Old = the numbers currently in `bench/*-macmini.json` / `bench/arkworks-mac.json` (`load1` = their recorded 1-min load); new = this rerun. Negative = faster on the quiet host.

| framework | K / config | old ms | old load1 | quiet ms | quiet load1 | change |
|---|---|---|---|---|---|---|
| arkworks | 10 full | 17.0 | 9.41 | 17.6 | 3.38 | +4 % |
| arkworks | 14 full | 142 | 9.41 | 139 | 3.38 | -2 % |
| arkworks | 18 full | 1791 | 10.64 | 1670 | 6.39 | -7 % |
| arkworks | 20 full | 12762 | 17.38 | 6573 | 7.45 | -48 % |
| gnark | 10 10 threads | 14.4 | 16.16 | 8.2 | 2.22 | -43 % |
| gnark | 14 10 threads | 194 | 16.16 | 69.4 | 2.22 | -64 % |
| gnark | 18 10 threads | 1250 | 18.70 | 800 | 5.68 | -36 % |
| gnark | 20 10 threads | 3331 | 20.14 | 2953 | 9.45 | -11 % |
| gnark | 10 1 thread | 45.8 | 20.14 | 45.1 | 3.41 | -2 % |
| gnark | 14 1 thread | 431 | 18.76 | 417 | 3.45 | -3 % |
| rapidsnark | 10 | 20.8 | 9–20 (not recorded) | 16.8 | 2.8–3.4 | -19 % |
| rapidsnark | 14 | 151 | 9–20 (not recorded) | 104 | 2.8–3.4 | -31 % |
| rapidsnark | 18 | 2723 | 9–20 (not recorded) | 1351 | 2.8–3.4 | -50 % |
| rapidsnark | 20 | 9792 | 9–20 (not recorded) | 5011 | 2.8–3.4 | -49 % |
| snarkjs | 10 | 402 | 9–20 (not recorded) | 255 | 2.8–3.4 | -37 % |
| snarkjs | 14 | 1419 | 9–20 (not recorded) | 935 | 2.8–3.4 | -34 % |
| snarkjs | 18 | 18425 | 9–20 (not recorded) | 9120 | 2.8–3.4 | -51 % |
| snarkjs | 20 | 59408 | 9–20 (not recorded) | 36000 | 2.8–3.4 | -39 % |
| Bend 2 (v2) | 10 10 threads | 627 | 2.11 | 629 | 3.91 | +0 % |
| Bend 2 (v2) | 10 `--threads 1` | 838 | 4.40 | 846 | 2.97 | +1 % |
| Bend 2 (v2) | 14 10 threads | 5469 | 2.46 | 6000 | 3.17 | +10 % |
| Bend 2 (v2) | 14 `--threads 1` | 11350 | 3.64 | 11456 | 2.98 | +1 % |
| Bend 2 (v2) | 18 10 threads | 33492 | 2.94 | 31836 | 2.61 | -5 % |
| Bend 2 MSM G1 (v1 defaults in JSON) | 2^16 10 threads | 1896 | quiet (v1) / 1 core busy (v2 md: 1184) | 1096 | 3.15 | -42 % |
| Bend 2 FFT | 2^16 10 threads | 47.0 | n/a | 26.0 | 2.79 | -45 % |
| arkworks MSM G1 | 2^16 | 54.2 | 9.39 | 49.5 | 3.65 | -9 % |
| gnark MSM G1 | 2^16 10 threads | 33.8 | 10.25 | 34.4 | 3.45 | +2 % |
| Bend 2 MSM G1 (v1 defaults in JSON) | 2^18 10 threads | 6547 | quiet (v1) / 1 core busy (v2 md: 3679) | 3160 | 3.15 | -52 % |
| Bend 2 FFT | 2^18 10 threads | 158 | n/a | 95.0 | 2.79 | -40 % |
| arkworks MSM G1 | 2^18 | 197 | 9.39 | 171 | 3.65 | -13 % |
| gnark MSM G1 | 2^18 10 threads | 124 | 10.25 | 115 | 3.50 | -8 % |
| Bend 2 MSM G1 (v1 defaults in JSON) | 2^20 10 threads | 20808 | quiet (v1) / 1 core busy (v2 md: 11087) | 10302 | 2.81 | -50 % |
| Bend 2 FFT | 2^20 10 threads | 529 | n/a | 389 | 2.79 | -26 % |
| arkworks MSM G1 | 2^20 | 666 | 10.32 | 641 | 4.00 | -4 % |
| gnark MSM G1 | 2^20 10 threads | 400 | 8.99 | 391 | 3.34 | -2 % |

## Ratios (Bend 2 ÷ comparator, 10 threads unless stated)

| K | Bend/gnark loaded → quiet | Bend/rapidsnark loaded → quiet | Bend/arkworks loaded → quiet | Bend/gnark 1 thread loaded → quiet |
|---|---|---|---|---|
| 10 | 44× → 77× | 30× → 37× | 37× → 36× | 18× → 19× |
| 14 | 28× → 86× | 36× → 58× | 38× → 43× | 26× → 27× |
| 18 | 27× → 40× | 12× → 24× | 19× → 19× | — |

Other pairs: arkworks/gnark 2^20 3.8× → 2.2×; rapidsnark/gnark 2^18 2.2× → 1.7×; Bend MSM G1 2^20 / gnark MSM G1 2^20 (v1 JSON 52×) → v2 quiet 26×; Bend FFT 2^20 / gnark FFT 2^20 18× → 17×.

## Does any conclusion change?

The ordering does not change (gnark < rapidsnark < arkworks ≪ snarkjs ≪ Bend 2 at every K), but the loaded comparator numbers were inflated by 1.3–2.8× while the Bend v2 numbers in `bench/bend2-macmini.json` were already taken at load1 2–5 and barely move (K=10 627→629, K=14 5469→6000, K=18 33492→31836 ms), so every Bend-vs-comparator ratio quoted from the loaded data understates the gap: Bend/gnark at 10 threads goes from 44×/28×/27× to **77×/86×/40×** (K=10/14/18), Bend/rapidsnark from 30×/36×/12× to **37×/58×/24×**, while Bend/arkworks is essentially unchanged (37×/38×/19× → 36×/43×/19×, arkworks was measured at load ≈ 9–10 rather than 17–20). The 1-thread Bend/gnark ratio is unchanged (18×→19× at K=10, 26×→27× at K=14): a single-`P` process was barely hurt by the contention, so the 10-thread comparator numbers were the ones that lied. Specific quotes that must be replaced: gnark 2^14 194 → 69 ms, gnark 2^18 1250 → 800 ms, gnark 2^20 3331 → 2953 ms, rapidsnark 2^18 2723 → 1351 ms and 2^20 9792 → 5011 ms, snarkjs 2^18 18425 → 9120 ms and 2^20 59408 → 36000 ms, arkworks 2^20 12762 → 6573 ms (arkworks 2^18 1791 → 1670 ms, ≤ 2^14 unchanged). Primitive comparisons hold: quiet Bend MSM G1 2^20 (10.3 s, v2) is 26× gnark's 391 ms and 16× arkworks' 641 ms; Bend FFT 2^20 389 ms is 17× gnark / 10× arkworks — so the MSM-add-bound story from `bend2/bench/msm_results.md` stands, and gnark's own primitives moved < 10 % (its MSMs had been benchmarked at load 7–11, not 17–20).

