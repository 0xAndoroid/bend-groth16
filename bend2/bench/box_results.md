# Bend 2 on the GPU box — CUDA (RTX 5090) + CPU (Threadripper 9960X)

2026-09-18, box `pika-bend-5090` (`docs/box.md`), repo `92ac2c4` (`bend-groth16-integration`). Re-run: `comparators/box/bend-cuda.sh`.
Raw lines: `/root/w3/results.txt`, `/root/w3/smi.log`, `/root/step1.log` on the box.

| | |
|---|---|
| Bend | **2.0.5** (`/root/.bend/bin/bend`, `BEND_NO_TELEMETRY=1`), clang **19.1.7** (apt.llvm.org), CUDA toolkit **12.8** (nvcc 12.8.93), driver 595.84 |
| GPU | RTX 5090, 32607 MiB, compute capability 12.0 → NVRTC `--gpu-architecture=sm_120` accepted (no error, kernel runs) |
| CPU | Threadripper 9960X 24C/48T, governor `powersave` (idle 400 MHz, boosts to 5.45 GHz under load), 125 GiB |
| Data | `ref/target/release/groth16-ref gen --log2 K` + `python3 bend2/tools/export_bin.py` for K = 4, 10, 14, 18, **20** (gen 29.9 s / 3.0 GB RSS, export 16.9 s / 4.1 GB RSS, 2.3 GB on disk) + `vectors`; `verify_bin.py data/4 data/10 --vectors` → `ALL OK` |

## CUDA status: works

- `bend field_mul.bend -o field_mul` = C build + NVRTC `--gpu-build` in **2.0 s** total (g1_add 3.0 s); NVRTC alone (`./bin --gpu-build`, `.gpu` removed) **0.49 s** → `field_mul.gpu` 82 KB, **1.03 s** → `g1_add.gpu` 213 KB. The `.gpu` is not a cubin/ELF (`cuobjdump: does not contain device code`) — Bend's own cache keyed by source hash.
- Missing/stale `.gpu` → `bend: compiling the GPU program (… is missing or stale)` at launch, process wall 0.49 s vs **0.12 s** cached (the 0.12 s is CUDA context + module load; hello-world-sized).
- `CONCURRENT_MANAGED_ACCESS` satisfied (managed-memory path runs, no trap); `--gpu 8GB` accepted, same ms; `--gpu off --threads 48` on the same binary reproduces the CPU numbers.
- **Every GPU checksum equals the CPU checksum of the same (N, FD)** (g1_add's `sum` depends on FD — the leaf chains start at different points; field_mul's `xor` does not).
- nvidia-smi peak `memory.used` during the runs: **1169 MiB** first pass, **1327 MiB** on the `bend-cuda.sh` re-run (1 Hz sampling; idle 2 MiB).

## `bend2/tests/run.sh` (CPU, box): PASS

`test_fr PASS 64 · test_fq PASS 64 · test_g1 PASS 32 · test_g2 PASS 16 · probe_show one 0x…01`, exit 0, 12.3 s wall incl. 5 builds.

## `field_mul` — 2^N `Fr.mul`, xor-folded (program's own `IO.now` ms; median of 3)

| N | CPU `--threads 1` FD14 | `--threads 24` FD14 | `--threads 48` FD14 | `--threads 48` FD16 | CUDA FD14 | FD16 | FD18 | FD20 | xor |
|---|---|---|---|---|---|---|---|---|---|
| 20 | 175 (6.0 M/s) | 14 | 13 | 13 | **2** | 2 | 2 | 2 | 21587 |
| 24 | 2720 (6.2 M/s) | 201 | 153 (110 M/s) | 153 | **3** | 2 | 3 | 2 | 33036 |
| 26 | — | — | — | 546 (123 M/s) | — | — | 6 | 6 | 8612 |
| 28 | — | — | — | 2098 (128 M/s) | — | — | 19 | **19** (14.1 G/s) | 1877 |
| 30 | — | — | — | — | — | — | — | **71** (15.1 G/s) | 54777 |

- 2^28: CUDA 19 ms vs CPU48 2098 ms → **110×**; vs M4 Metal (73 ms at 2^24, `README.md`) ≈ 60× in throughput. `--gpu 8GB` 19 ms; `--gpu off --threads 48` 2143 ms (same binary, same xor).
- Below 2^26 the GPU run is timer-floor bound (1–3 ms incl. the `!` dispatch); the ~55 ms Metal dispatch cost does not exist on CUDA. FD is irrelevant from 14 to 20.
- CPU: 24 → 48 threads gives 1.3× (SMT); 1 → 48 threads 17.8× at 2^24. Single-thread is 0.67× the M4 (2720 vs 1829 ms).

## `g1_add` — 2^N `G1.add_mixed` chains (median of 3; single runs where noted)

| N | FD | CPU `--threads 1` | `--threads 24` | `--threads 48` | CUDA | sum (CPU = CUDA) |
|---|---|---|---|---|---|---|
| 20 | 14 | 2290 (0.46 M/s) | 177 | 134 (7.8 M/s) | **4** | 917307392 |
| 20 | 16 | — | — | 146 | 3 | 1523843072 |
| 20 | 18 | — | — | 203 (1 run) | 4 | 2728394752 |
| 22 | 16 | — | — | 477 | **6** | 3669229568 |
| 22 | 18 | — | — | 455 (1) | 7 | 1800404992 |
| 22 | 20 | — | — | 490 (1) | 7 | 2323644416 |
| 24 | 18 | — | — | 1716 (1) | **18** | 1792016384 |
| 24 | 20 | — | — | 1736 (1) | 19 (`--gpu 8GB` 19) | 2906652672 |
| 26 | 20 | — | — | 6776 (`--gpu off`, 1) | **65** (1.03 G/s) | 2873098240 |

- 2^26: CUDA 65 ms vs CPU48 6776 ms → **104×**; M4 Metal was 99 ms at 2^20 (10.6 M/s) → ~100× in throughput.
- Scaling is linear from 2^24 (18 ms) to 2^26 (65 ms); 2^20–2^22 sit on the 3–7 ms floor.

## For the prover lane

- Path is clear: `bend f.bend -o f` on the box builds the CUDA program in the same step. Bend's `cc_find` tries `$CC`, `clang`, then every `clang-NN` on PATH newest-first and needs clang ≥ 19 for a `!` program — stock `/usr/bin/clang` is 18, `/usr/bin/clang-19` (apt.llvm.org) is picked up automatically.
- Expect the `!` phases (MSM/NTT) to sit on a 2–7 ms floor below ~2^22 and to run ~100× faster than CPU48 above; the CUDA `--gpu` span default is not documented (`--help`: "over 2GB on Metal") — pass `--gpu 8GB` if a K=20 phase traps on memory (the benches allocate little, so untested here).
- `uv` is not on the box; `bend2/scripts/prove.sh` calls `uv run python` and `cargo run` — use `python3` + `ref/target/release/groth16-ref verify` directly, or install uv.
- Step 4 (msm/ntt benches, `prove.sh` with `MODE=gpu`) skipped: `bend2/src/msm.bend`/`ntt.bend` do not exist on `bend-groth16-integration` at `92ac2c4`, `prove.bend` imports `naive.bend`.
