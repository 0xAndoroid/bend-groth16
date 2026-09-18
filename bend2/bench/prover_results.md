# Bend 2 Groth16 prover — full-prover numbers (`bend2/prove.bend`)

2026-09-18, Bend 2.0.5, lane w3 bend2-prover-bench 1/3. Every run below printed `OK` (arkworks verify) and `EQUAL`
(A, B, C bit-identical to `data/K/proof_ref.json`). Raw per-run JSON: `bench/bend2-macmini.json`, `bench/bend2-box.json`
(`prove` = MSM **v2**, `prove_v1` = MSM v1; `msm_g1`, `msm_g1_v1`, `ntt` primitives). Runner: `bend2/scripts/bench_prover.sh`
(`run CFG RUNS K [args]` → one JSON line per `prove.sh` run; `merge META OUT RUNS` → the bench file).

- **MSM v1** = `a2d704a` (`Msm.pick_c` 8 / 12 from 2^18, `pick_fd` min(4, log2n − c)); **MSM v2** = `788b49e`
  (c 8 / 10 from 2^20, fd min(7, log2n − c − 1)). NTT and everything else identical between the two.
- `cpu1` = `--threads 1`; `cpu_all` = `prove.sh` default on the mini (10 threads) / `--threads 48` on the box.
- `gpu` = `BENDG_GPU=1` (`d524023`: one `!` per MSM phase and for `qap_h`; Metal on the mini, CUDA on the box with
  `--gpu 16GB`). Mini K=18 needs `--gpu 8GB` — the default span dies with `bend: out of memory`. The v1 tables predate
  the switch and have no gpu rows.
- ms are the prover's own `T` lines (medians; `samples` = per-run totals); `load1` = 1-min load average at the start of
  each run (other lanes were active on the mini during v1 — load 6–15 on 10 cores — and quieter, 2–6, during v2).
  The bend compile (~15 s) and the arkworks verify are outside the timers.

## Mini (Apple M4, 10 cores, 16 GB) — MSM v2

| K | config | load | evals | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l | **total** | samples | OK/EQUAL | load1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | cpu1 | 1 | 0 | 1 | 30 | 21 | 62 | 21 | 19 | **159** | 160 159 150 | OK+EQUAL | 5.89/5.49/4.80 |
| 4 | cpu_all | 1 | 0 | 4 | 16 | 13 | 34 | 12 | 10 | **95** | 99 86 95 | OK+EQUAL | 1.94/2.02/2.24 |
| 10 | cpu1 | 3 | 1 | 23 | 102 | 101 | 322 | 181 | 100 | **838** | 838 839 838 | OK+EQUAL | 4.40/4.00/3.92 |
| 10 | cpu_all | 7 | 1 | 14 | 86 | 83 | 259 | 99 | 73 | **627** | 630 625 627 | OK+EQUAL | 2.11/2.16/2.42 |
| 14 | cpu1 | 47 | 10 | 381 | 1356 | 1358 | 4281 | 2598 | 1325 | **11350** | 11351 11343 11350 | OK+EQUAL | 3.64/3.42/3.28 |
| 14 | cpu_all | 47 | 11 | 83 | 764 | 759 | 2384 | 783 | 631 | **5469** | 5461 5469 5479 | OK+EQUAL | 2.46/2.55/2.45 |
| 18 | cpu_all | 734 | 163 | 1342 | 4082 | 4176 | 13808 | 5919 | 3261 | **33491** | 34267 32716 | OK+EQUAL | 2.94/5.80 |
| 4 | gpu (Metal) | 1 | 0 | 70 | 140 | 137 | 419 | 158 | 134 | **1061** | 1061 1071 1060 | OK+EQUAL | 2.42/2.73/3.11 |
| 10 | gpu (Metal) | 4 | 1 | 130 | 1342 | 1341 | 6523 | 1848 | 2195 | **13389** | 13389 13388 13393 | OK+EQUAL | 2.73/2.39/2.40 |
| 14 | gpu (Metal) | 52 | 10 | 331 | 4025 | 4029 | 18418 | 4461 | 3715 | **35047** | 35060 35035 | OK+EQUAL | 2.33/2.33 |
| 18 | gpu (Metal, `--gpu 8GB`) | 771 | 162 | 2478 | 27647 | 27869 | 116589 | 41630 | 22386 | **239536** | 239536 | OK+EQUAL | 2.37 |

K=18 `cpu1` was not re-run on v2 (v1 row below: 97.7 s; K=14 1-thread is 11 s, so the 1-thread K=18 v2 estimate from the
v1 → v2 ratio at K=14, 1.30×, is ≈ 125 s).

### Mini — MSM v1 (same data, run first)

| K | config | load | evals | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l | **total** | samples | OK/EQUAL | load1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | cpu1 | 1 | 0 | 1 | 26 | 20 | 82 | 28 | 20 | **200** | 200 201 147 | OK+EQUAL | 8.47/10.35/9.68 |
| 4 | cpu_all | 1 | 0 | 3 | 20 | 20 | 42 | 19 | 18 | **135** | 160 135 104 | OK+EQUAL | 11.81/14.78/13.81 |
| 10 | cpu1 | 4 | 1 | 24 | 121 | 120 | 377 | 210 | 114 | **976** | 976 975 976 | OK+EQUAL | 8.58/7.80/6.82 |
| 10 | cpu_all | 4 | 0 | 15 | 100 | 101 | 318 | 120 | 68 | **732** | 732 815 712 | OK+EQUAL | 12.30/10.68/9.35 |
| 14 | cpu1 | 54 | 11 | 390 | 1007 | 1003 | 3136 | 1987 | 1129 | **8722** | 8722 8671 8752 | OK+EQUAL | 7.02/6.64/6.18 |
| 14 | cpu_all | 48 | 10 | 98 | 974 | 974 | 3011 | 987 | 571 | **6678** | 6699 6678 6615 | OK+EQUAL | 8.37/6.86/6.11 |
| 18 | cpu1 | 750 | 165 | 6644 | 11049 | 11002 | 33804 | 21907 | 12381 | **97707** | 97707 | OK+EQUAL | 3.95 |
| 18 | cpu_all | 756 | 164 | 1304 | 14397 | 14285 | 35648 | 13148 | 8901 | **88610** | 85984 91236 | OK+EQUAL | 5.00/5.52 |

## Box (Threadripper 9960X 24C/48T, RTX 5090) — MSM v2

| K | config | load | evals | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l | **total** | samples | OK/EQUAL | load1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | cpu1 | 5 | 1 | 35 | 156 | 143 | 472 | 256 | 140 | **1213** | 1212 1213 1254 | OK+EQUAL | 5.48/4.48/3.56 |
| 10 | cpu_all | 5 | 1 | 14 | 110 | 107 | 339 | 136 | 148 | **860** | 884 860 855 | OK+EQUAL | 3.17/2.69/2.45 |
| 14 | cpu1 | 58 | 16 | 527 | 1901 | 1896 | 6313 | 3692 | 1859 | **16284** | 16240 16314 16284 | OK+EQUAL | 2.99/2.20/1.73 |
| 14 | cpu_all | 59 | 16 | 62 | 515 | 520 | 1670 | 562 | 318 | **3728** | 3728 3739 3722 | OK+EQUAL | 2.37/2.06/2.00 |
| 18 | cpu_all | 883 | 239 | 721 | 4729 | 4708 | 15765 | 5075 | 2777 | **34906** | 34917 34896 | OK+EQUAL | 1.96/3.59 |
| 20 | cpu_all | 3502 | 926 | 2665 | 15458 | 15385 | 51602 | 16476 | 8980 | **115003** | 115032 114975 | OK+EQUAL | 4.30/5.30 |
| 10 | gpu (CUDA) | 7 | 1 | 48 | 509 | 508 | 1826 | 701 | 876 | **4484** | 4488 4481 4484 | OK+EQUAL | 0.13/0.70/0.92 |
| 14 | gpu (CUDA) | 72 | 17 | 144 | 1501 | 1495 | 5178 | 1679 | 1366 | **11461** | 11461 11466 11454 | OK+EQUAL | 1.03/1.18/1.07 |
| 18 | gpu (CUDA) | 1078 | 254 | 1731 | 8720 | 8895 | 21709 | 8877 | 4809 | **56083** | 56197 55969 | OK+EQUAL | 1.28/1.05 |
| 20 | gpu (CUDA) | 3898 | 984 | 8583 | 32282 | 33003 | 77240 | 32690 | 18598 | **207286** | 207402 207170 | OK+EQUAL | 1.04/1.01 |

nvidia-smi (1 Hz) during the CUDA prover rows: peak `memory.used` **21257 MiB** (K=20), `utilization.gpu` 100 % whenever a
phase kernel is resident (55 % of the wall-clock samples; the rest is host-side load/evals and the per-phase upload).

### Box — MSM v1

| K | config | load | evals | qap | msm_a | msm_b1 | msm_b2 | msm_h | msm_l | **total** | samples | OK/EQUAL | load1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | cpu1 | 5 | 1 | 36 | 173 | 167 | 553 | 300 | 163 | **1402** | 1401 1402 1404 | OK+EQUAL | 6.07/4.95/3.89 |
| 10 | cpu_all | 5 | 1 | 14 | 66 | 67 | 207 | 91 | 82 | **537** | 533 537 538 | OK+EQUAL | 1.54/1.42/1.33 |
| 14 | cpu1 | 58 | 16 | 527 | 1360 | 1361 | 4543 | 2676 | 1549 | **12099** | 12099 12141 12073 | OK+EQUAL | 3.25/2.48/1.95 |
| 14 | cpu_all | 61 | 16 | 62 | 400 | 394 | 1260 | 428 | 275 | **2900** | 2891 2911 2900 | OK+EQUAL | 1.25/1.33/1.25 |
| 18 | cpu_all | 885 | 247 | 723 | 4242 | 4220 | 13694 | 4664 | 2955 | **31638** | 31732 31545 | OK+EQUAL | 1.61/2.72 |
| 20 | cpu_all | 3493 | 931 | 2662 | 13942 | 13858 | 45371 | 14811 | 8045 | **103122** | 103295 102949 | OK+EQUAL | 3.44/4.78 |

## Box primitives (`bend2/bench/msm.bend` G1, `bench/ntt.bend` fft; ms, median of 3, checksums equal across configs)

CUDA = `MODE=gpu … --gpu 16GB`; the FD sweep tried {default, 9, 11} (msm, clamped to log2n − c − 1) and {10, 12, 14} (ntt);
best value shown, alternatives in parentheses. 2^18 / 2^20 GPU MSM rows are single runs. `bend2/tests/test_msm` (v1 and v2,
exit 0) and `test_ntt` PASS on the box (`msm_small_{8,64,1024}`, `ntt_small_{8,64,1024}`).

| n | MSM v2 `--threads 1` | v2 `--threads 48` | v2 CUDA (fd) | MSM v1 `--threads 1` | v1 `--threads 48` | v1 CUDA (fd) |
|---|---|---|---|---|---|---|
| 2^10 | 191 | 199 | 2006 (1) | 174 | 96 | 466 (2) |
| 2^12 | 547 | 182 | 2025 (3) | 598 | 160 | 928 (4) |
| 2^14 | 1958 | 376 | 2502 (5) | 1608 | 292 | 1397 (6; fd4 1425) |
| 2^16 | 7612 | 1104 | 2978 (7) | 5120 | 780 | 2109 (8; fd4 3379, fd6 2170) |
| 2^18 | — | 2942 | **4273** (9; fd7 4703) | — | 3169 | 16989 (6; fd4 17482) |
| 2^20 | — | 9521 | **17075** (9; fd7 18528) | — | 8577 | 29341 (8; fd4 43250, fd6 30009) |

| n | NTT fft `--threads 1` | `--threads 48` | CUDA (fd) |
|---|---|---|---|
| 2^10 | 6 | 7 | 12 (9) |
| 2^12 | 14 | 13 | 21 (10) |
| 2^14 | 41 | 20 | 47 (10) |
| 2^16 | 146 | 48 | 142 (10; fd12 145, fd14 146) |
| 2^18 | — | 168 | 517 (10; fd12 523, fd14 530) |
| 2^20 | — | 423 | 3133 (12; fd10 3157, fd14 3146) |

nvidia-smi (1 Hz) during the CUDA MSM runs: peak `memory.used` **12983 MiB** (v2, 2^20 fd 9, c 10) / **16695 MiB** (v1, 2^20 fd 8,
c 12), `utilization.gpu` 100 % whenever a leaf kernel was resident (73 % average over the small-size sweep, where launches and
host-side joins dominate). Mini primitive numbers (Metal) are in `msm_results.md` / `ntt_results.md`; only the v1 G1 series
(`msm_g1_v1`) and the fft series (`ntt`) are copied into `bench/bend2-macmini.json` — the mini v2 MSM table has no JSON series.
The mini Metal MSM rows at 2^14 / 2^16 used c = 10 / 12 (CPU rows c = 8), so those CPU/GPU pairs are not fixed-config ratios.

Caveat on the CPU rows: they were taken with the bang-bearing binary (`d524023`+) without `--gpu off`, so the runtime's
GPU-backed arena was active; the v1 rows predate the GPU switch. "Everything else identical" between v1 and v2 therefore
holds for the source, not necessarily for the binary.

## Where the time goes

The prover is ~90 % MSM at every size and on both hosts: at K=18 the five MSMs are 31.2 of 33.5 s on the mini (10 threads, v2) and
33.1 of 34.9 s on the box (48 threads); load + evals + qap are 5 % (box) / 7 % (mini) and everything else is noise. The single G2 MSM (`msm_b2`, 2^18
points over Fq2) is the largest phase — 41–45 % of the total, ≈ 3.3× a G1 MSM of the same size, because every Fq2 mul is three
Fq muls and the Jacobian G2 add carries 96-word points through the bucket arrays. The 2^19-point `msm_h` is the second (15–17 %),
then `msm_a` / `msm_b1` (12 % each) and the shorter `msm_l` (8–9 %); `qap` (7 NTT passes at 2^19) is 4 % on the mini and 2 % on
the box. Threads help the MSMs far less than the NTTs: 1 → 10 threads at K=14 gives 2.1× on the whole prover (msm_b2 1.8×, qap
4.6×), 1 → 48 threads on the box 4.4× (msm_b2 3.8×, qap 8.5×). Hypothesis (not isolated by measurement): the bucket join and
the per-leaf array copies, not raw arithmetic, bound the parallel MSM. MSM v2 (more leaves, smaller windows) is a clear win on the M4 — K=18 10-thread 88.6 → 33.5 s
(2.6×), K=14 6.7 → 5.5 s — but a regression on the Threadripper — 48-thread K=20 103 → 115 s (+12 %), K=14 2.9 → 3.7 s, 1-thread
K=14 12.1 → 16.3 s (hypothesis: v1's 16 large leaves with c=12 already kept 48 threads busy and v2's 128 leaves × 32 windows add
join work; not isolated). The GPU switch does not rescue the prover either:
`BENDG_GPU=1` is 1.8× slower than CPU48 on the box (K=20 207 s vs 115 s; K=18 56 vs 35 s; K=10 4.5 vs 0.86 s) and 7× slower than
10 CPU threads on the M4 (K=18 240 s vs 33.5 s), with the same shape as the primitives — the best CUDA 2^20 G1 MSM is 17.1 s vs
9.5 s on 48 threads, the CUDA NTT 7× slower than CPU48 at 2^20 (3.1 s vs 0.42 s); the G2 phase suffers most (CUDA K=20
`msm_b2` 77 s vs 52 s). Hypothesis: a `!` runs a few hundred leaves, each a sequential GPU thread, so the device is far
under-occupied even while `nvidia-smi` (1 Hz) reads 100 % — the occupancy was not measured. A GPU-competitive prover likely
needs a bucket-sorted MSM with a shared read-only point array (an owned sorted/segmented design is possible without shared
arrays, see `docs/used-properly-audit.md`) and a device-filling NTT (a stage-parallel NTT exists, `src/ntt.bend:152`; it
underfills the device); on CPU the next lever is the G2 MSM (GLV/endomorphism or a cheaper G2 add path) and a parallel bucket join.
