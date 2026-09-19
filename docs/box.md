# CUDA box — hardware, toolchain, reproduction

Every `bench/box-*.json` and `bench/bend2-box.json` row, `bend2/bench/box_results.md` and the box half of
`bend2/bench/prover_results.md` were measured on one rented RTX 5090 machine (a GPU-rental marketplace instance; any
Ubuntu 24.04 / CUDA 12.8 host with the same class of GPU reproduces the setup). Current Bend results:
`bend2/bench/prover_results.md`, `bend2/bench/box_results.md`, `bench/bend2-box.json`; summary in `docs/benchmarks.md`.

## Hardware snapshot

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 5090, 32607 MiB, compute capability **12.0** (sm_120) |
| driver / CUDA | driver 595.84; toolkit **nvcc 12.8.93** |
| CPU | AMD Ryzen Threadripper 9960X, 24 cores / 48 threads (Zen 5, AVX-512); governor `powersave` (idle 400 MHz, boosts to 5.45 GHz) |
| RAM / disk | 125 GiB, 100 GB overlay disk |
| OS | Ubuntu 24.04.1 (container image with CUDA 12.8 devel) |
| container | 47 Go threads visible to gnark (`GOMAXPROCS=47`); Bend uses `--threads 48` |

## Toolchain versions

| tool | version |
|---|---|
| Go | 1.25.7 (`/usr/local/go`) |
| Rust | 1.95 (`$HOME/.cargo/bin`) |
| Node / snarkjs / circom | 22.23 / 0.7.6 / 2.2.3 |
| clang | 19.1.7 (apt.llvm.org; Bend's `!` programs need clang ≥ 19 — stock Ubuntu clang 18 is rejected) |
| Bend | 2.0.5 (`curl -fsSL https://bend-lang.com/install.sh \| BEND_NO_TELEMETRY=1 sh` → `$HOME/.bend`) |
| gnark / icicle-gnark | v0.16.3 / v3.2.2 |
| rapidsnark | v0.0.8 |
| ICICLE-SNARK | bf00385 |
| open-icicle | v4.0.0 |
| sppark | v0.1.15 |

## Layout

All scripts take their paths from environment variables with these defaults:

| variable | default | content |
|---|---|---|
| `REPO` | the checkout containing the script | this repository |
| `DEV` | `/root/dev` | pinned comparator sources: `rapidsnark`, `icicle-gnark`, `icicle-snark`, `open-icicle`, `sppark` |
| `ART` | `/root/art` | builds and artifacts: `square-K/` (Circom `circuit.r1cs`, `witness.wtns`, `circuit.zkey`, `vk.json` for K=10,14,18,20), `potP.ptau` (PSE `ppot_0080_P.ptau`, P = K+1), `gnark-install`, `snark-install`, `icicle4-install` (isolated ICICLE prefixes, all `-DCUDA_ARCH=120`), `gnark-cpu` / `gnark-icicle` runner binaries |
| `TOOLS` | `/root/tools` | `circom` binary and `node_modules/.bin/snarkjs` |

`comparators/gpu/icicle-prim/Cargo.toml` reaches `open-icicle` through the gitignored symlink `comparators/gpu/icicle-prim/open-icicle` (`build.sh` creates it: `ln -sfn $DEV/open-icicle comparators/gpu/icicle-prim/open-icicle`).

## Steps

1. One-time setup, comparator builds and Circom artifacts: `comparators/box/README.md` (`build.sh`, `gen-all.sh`).
2. Circuit check: `snarkjs r1cs info` per K must report constraints = 2^K exactly, wires = 2^K + 2, 1 private input,
   1 output, 0 public inputs; the gnark runner asserts `GetNbConstraints() == N`.
3. CPU comparators: `comparators/box/run-cpu.sh` → `bench/box-cpu-{gnark,gnark-1thread,rapidsnark,snarkjs}.json`.
4. GPU comparators: `comparators/gpu/run-gpu.sh` → `bench/box-gpu-{gnark-icicle,gnark-icicle-pinned,icicle-snark,primitives}.json`.
5. Bend 2 smoke test (interpreter, C build, CUDA `!` build): `comparators/box/bend-smoke.sh`.
6. Bend 2 primitive benches on CUDA: `comparators/box/bend-cuda.sh` → `bend2/bench/box_results.md`.
7. Bend 2 prover: `BENDG_GPU=1 sh bend2/scripts/prove.sh K --gpu 16GB` (CUDA) and `sh bend2/scripts/prove.sh K --threads 48` (CPU);
   `bend2/scripts/bench_prover.sh` produces the `bench/bend2-box.json` rows.

Run one benchmark process at a time on an otherwise idle box; every JSON row records the 1-minute load average.

## Results — box CPU (Threadripper 9960X, 24C/48T)

SquareChain(2^K), BN254, median wall ms, every proof verified. What each timer includes differs — read the row label.

| K | gnark v0.16.3 all cores (prove incl. solver) | gnark GOMAXPROCS=1 | rapidsnark v0.0.8 CLI (cold: zkey+wtns load + prove + write) | snarkjs 0.7.6 CLI (cold, node) |
|---|---|---|---|---|
| 10 | **3.6** (5 runs; solve 0.5) | 35.3 | 22.0 (5) | 372.9 (5) |
| 14 | **19.0** (5; solve 1.0) | 321.2 | 60.5 (5) | 669.1 (5) |
| 18 | **189.4** (3; solve 9.7) | — | 643.9 (3) | 2894 (2) |
| 20 | **665.7** (3; solve 43.2) | — | 2031 (2) | 10663 (1) |

- gnark: `groth16.Setup` 19 / 151 / 1872 / 7339 ms; first (cold) prove within ±5 % of warm.
- rapidsnark numbers are process launches (file-inclusive): the 562 MB K=20 zkey is read from page cache each run, so this is an upper bound on its in-memory prove time (the CLI has no warm-prove mode; see `docs/comparators.md`).
- snarkjs K=20 is a single run (10.7 s); QAP domain for snarkjs is 2N (adds public/constant rows), gnark uses N.
- Files: `bench/box-cpu-gnark.json`, `bench/box-cpu-gnark-1thread.json`, `bench/box-cpu-rapidsnark.json`, `bench/box-cpu-snarkjs.json`.

## Results — RTX 5090 provers

Same SquareChain rows; median wall ms. Verification scope: gnark and gnark+ICICLE verify every timed proof; ICICLE-SNARK: only the final proof per size is verified (the worker overwrites one proof file across cold + warm runs).

| K | gnark CPU (ref, all cores) | **gnark v0.16.3 + icicle-gnark v3.2.2** (`icicleGroth.Prove`, PK not pinned) | same, `WithPinKeysToGPU` | **ICICLE-SNARK bf00385** (`--device CUDA`, zkey cached) | ICICLE-SNARK cold (1st prove, zkey parse + H2D) |
|---|---|---|---|---|---|
| 10 | 3.6 | 26.5 (5) | 26.1 (5) | 19.7 (5) | 134.7 |
| 14 | 19.0 | 31.2 (5) | 30.1 (5) | 21.3 (5) | 26.1 |
| 18 | 189.4 | **48.3** (3) | 44.4 (3) | **41.3** (5) | 73.1 |
| 20 | 665.7 | **203.2** (3) | 180.6 (3) | **114.3** (5) | 232.9 |

- gnark+ICICLE time = gnark constraint solver (`solve_ms` 0.2 / 1.5 / 9.7 / 40.6 ms — CPU) + H2D of witness-dependent vectors + GPU MSMs/NTTs + proof D2H; PK vectors are re-uploaded each proof unless pinned. Speed-up vs gnark CPU on this box: K=18 3.9× (4.3× pinned), K=20 3.3× (3.7× pinned); K≤14 is *slower* than CPU (≈26 ms fixed launch/transfer floor). Built with `-DCUDA_ARCH=120` on CUDA 12.8; valid verified proofs at all K. First prove of a process includes ICICLE backend load + device warm-up (`first_prove_ms` 289 ms at K=10).
- ICICLE-SNARK: worker's own `proof took` timer; includes reading `witness.wtns` from disk (32 MB at K=20) and writing proof/public JSON, excludes zkey parsing (cached). Driver-side wall agrees within 0.1 ms for the warm medians (the first command of a process includes start-up: `first_wall_ms` 146 vs `first_prove_ms` 135 at K=10). No witness solving (Circom wtns pre-generated) — so vs gnark+ICICLE subtract ~41 ms of solver at K=20 for a like-for-like view. Experimental per upstream README.
- Files: `bench/box-gpu-gnark-icicle.json`, `bench/box-gpu-gnark-icicle-pinned.json`, `bench/box-gpu-icicle-snark.json`.

## Results — RTX 5090 primitives (BN254 G1 MSM, Fr radix-2 NTT; ms)

ICICLE rows: median of 10 after 1 warm-up. sppark MSM: Criterion estimate (20 samples, 1 s warm-up).

| 2^k | ICICLE v4 MSM device-resident (kernel only) | ICICLE v4 MSM host scalars (H2D scalars, cached bases) | sppark v0.1.15 MSM `multi_scalar_mult_arkworks` (H2D points+scalars each call) | ICICLE v4 NTT fwd device in-place | ICICLE v4 NTT fwd host in/out | sppark NTT fwd host in-place (H2D+D2H) |
|---|---|---|---|---|---|---|
| 10 | 2.28 | 2.91 | 1.91 | 0.025 | 0.193 | 0.029 |
| 12 | 2.61 | 3.17 | 2.05 | 0.025 | 0.144 | 0.038 |
| 14 | 2.84 | 3.68 | 3.04 | 0.030 | 0.193 | 0.093 |
| 16 | 2.78 | 3.80 | 7.91 | 0.055 | 0.317 | 0.217 |
| 18 | 3.55 | 4.83 | 24.7 | 0.140 | 0.739 | 0.689 |
| 19 | 4.83 | 5.20 | 47.2 | 0.249 | 1.373 | 1.335 |
| 20 | **7.17** | 7.39 | 92.0 | **0.622** | 2.96 | 2.63 |

- ICICLE (open-icicle v4.0.0, `-DCUDA_ARCH=120`, `comparators/gpu/icicle-prim`): synchronous calls (`is_async=false`), precompute factor 1, `c` auto, batch 1; device result == host-path result at every size; NTT round-trip `ifft(fft(x)) == x` at every size (checked through the host-buffer API); twiddle domain for 2^20 initialised once (1.1 ms, untimed). MSM has a ≈2.3 ms floor below 2^17 (kernel-launch/bucket setup bound). ICICLE's stock criterion benches were not used (their timer is async with sync outside the loop).
- sppark MSM is the shipped `poc/msm-cuda` criterion bench (`BENCH_NPOW=k`, `--features bn254`; sm_120 selected by sppark's nvcc probe); its API takes host arkworks 0.3 slices and copies points **and** scalars every call, so it is host-inclusive and not comparable to the device-resident ICICLE column (2^20: 64 MB points + 32 MB scalars per call). sppark ships no BN254 NTT timing bench; `comparators/gpu/sppark/ntt_timer.rs` times `ntt_cuda::NTT/iNTT` (host in-place, round-trip checked).
- File: `bench/box-gpu-primitives.json` (`icicle.*`, `sppark.*`, per-size samples).

## Bend 2 on the box

- Install: `curl -fsSL https://bend-lang.com/install.sh | BEND_NO_TELEMETRY=1 sh` → `$HOME/.bend` (`$HOME/.bend/bin/bend`; installs bun into `$HOME/.bun`). `bend --version` = **bend 2.0.5**. PATH: `export PATH=$HOME/.bend/bin:$HOME/.bun/bin:/usr/local/cuda/bin:$PATH`.
- CLI: `bend file.bend` = check + run (interpreter, 74 ms for hello); `bend file.bend -o out` = native binary; `-o out.c` emits one C file.
- C target: `bend hello.bend -o hello` → 1.1 MB binary (libc/libm only). 0.3 s build.
- CUDA target: a program using `!` needs **clang ≥ 19** (`bash llvm.sh 19` from apt.llvm.org). `bend pow2.bend -o pow2` builds in 0.76 s, links `libcuda.so.1` + `libnvrtc.so.12` (kernels are NVRTC-JIT'd at run time into a `.gpu` cache next to the binary; emitted C contains `__global__ void bend_dev(...)`). Run 0.12 s.
- `uv` is not needed on the box: `bend2/scripts/prove.sh` calls `uv run python`; the exporters are stdlib-only, so `python3 bend2/tools/export_bin.py` + `ref/target/release/groth16-ref verify` work directly.
- Smoke script: `comparators/box/bend-smoke.sh`; benches: `comparators/box/bend-cuda.sh`.

## Cost

All comparator runs took ~1.3 h of box time; the whole session (comparators + Bend CUDA benches + prover rows) was under 3 h at about $0.63/h.
