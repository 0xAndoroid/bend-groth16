---
created: 2026-09-18
updated: 2026-09-18
tags: [bend-groth16, gpu, benchmark]
---
# GPU box — `pika-bend-5090`

Rented 2026-09-18 05:47 UTC by lane `bend-groth16 · w1 gpu-box`. **Not destroyed by this lane** — the Bend-CUDA lane reuses it; the orchestrator tears it down (`echo y | vastai destroy instance 51392026`).

| | |
|---|---|
| vast.ai instance | **51392026** (offer 50511172), label `pika-bend-5090`, Virginia US |
| price | **$0.628/h** (offer listed $0.601 + storage) |
| GPU | NVIDIA GeForce RTX 5090, 32607 MiB, compute capability **12.0** (sm_120) |
| driver / CUDA | driver 595.84 (cuda_max_good 13.2); toolkit in image **nvcc 12.8.93** |
| CPU | AMD Ryzen Threadripper 9960X, 24 cores / 48 threads (Zen 5, AVX-512), 125 GiB RAM, 100 GB overlay disk |
| OS / image | Ubuntu 24.04.1, `ghcr.io/0xandoroid/pika-vast:latest` (`PIKA_SKIP_SHIM=1`, shim not registered) |
| ssh (direct) | `ssh -i ~/.ssh/vast_jolt -p 50189 root@204.111.84.239` — key `vast_jolt` on the mini; also `~/.ssh/id_ed25519`-independent |
| machine file | `$TMPDIR/bend-groth16/box.json` on the mini (`instance_id, ip, port, key, dph`) |

## Layout on the box

| path | content |
|---|---|
| `/root/bend-groth16` | this repo, branch `bend-groth16-integration` |
| `/root/w1` | rsync of this lane's `comparators/` (scripts are run from here; `REPO=/root/w1`) |
| `/root/dev/{rapidsnark,icicle-gnark,icicle-snark,open-icicle,sppark}` | pinned sources: v0.0.8, v3.2.2, bf00385, v4.0.0, v0.1.15 |
| `/root/art/square-K/` | Circom SquareChain(2^K) artifacts: `circuit.r1cs`, `witness.wtns`, `circuit.zkey`, `vk.json` (K=10,14,18,20) |
| `/root/art/potP.ptau` | PSE perpetual-powers-of-tau prepared files `ppot_0080_P.ptau`, P = K+1 (Hermez GCS/S3 URLs now 403) |
| `/root/art/gnark-install`, `snark-install`, `icicle4-install` | isolated ICICLE prefixes (icicle-gnark v3.2.2 all 4 curves · ICICLE-SNARK's vendored icicle · open-icicle v4.0.0 bn254), all `-DCUDA_ARCH=120` |
| `/root/art/gnark-cpu`, `/root/art/gnark-icicle` | Go runner binaries (`comparators/gpu/gnark-icicle`), the latter built with `-tags=icicle` |
| toolchains | Go 1.25.7 `/usr/local/go`; Rust 1.95 `/home/pika/.cargo/bin` (`CARGO_HOME/RUSTUP_HOME` point at `/home/pika`); Node 22.23; snarkjs 0.7.6 in `/root/tools/node_modules/.bin`; circom 2.2.3 `/root/tools/circom` |
| logs | `/root/setup.log`, `/root/build.log`, `/root/gen.log`, `/root/art/gen-K.log`, `/root/cpu.log`, `/root/gpu.log` |

## Circuit check

`snarkjs r1cs info` per K (`/root/art/square-K/r1cs-info.txt`): constraints = 2^K exactly, wires = 2^K + 2, 1 private input, 1 output, 0 public inputs. gnark runner asserts `GetNbConstraints() == N`.

## Results — box CPU (Threadripper 9960X, 24C/48T; container exposes GOMAXPROCS=47)

SquareChain(2^K), BN254, median wall ms, every proof verified. What each timer includes differs — read the row label.

| K | gnark v0.16.3 all cores (prove incl. solver) | gnark GOMAXPROCS=1 | rapidsnark v0.0.8 CLI (cold: zkey+wtns load + prove + write) | snarkjs 0.7.6 CLI (cold, node) |
|---|---|---|---|---|
| 10 | **3.6** (5 runs; solve 0.5) | 35.3 | 22.0 (5) | 372.9 (5) |
| 14 | **19.0** (5; solve 1.0) | 321.2 | 60.5 (5) | 669.1 (5) |
| 18 | **189.4** (3; solve 9.7) | — | 643.9 (3) | 2894 (2) |
| 20 | **665.7** (3; solve 43.2) | — | 2031 (2) | 10663 (1) |

- gnark: `groth16.Setup` 19 / 151 / 1872 / 7339 ms; raw PK 0.39 MB (K=10) … see `pk_bytes` in the JSON; first (cold) prove within ±5 % of warm.
- rapidsnark numbers are process launches (file-inclusive): the 562 MB K=20 zkey is read from page cache each run, so this is an upper bound on its in-memory prove time (the CLI has no warm-prove mode; see `docs/comparators.md`).
- snarkjs K=20 is a single run (10.7 s); QAP domain for snarkjs is 2N (adds public/constant rows), gnark uses N.
- Files: `bench/box-cpu-gnark.json`, `bench/box-cpu-gnark-1thread.json`, `bench/box-cpu-rapidsnark.json`, `bench/box-cpu-snarkjs.json`.

## Results — RTX 5090 provers

Same SquareChain rows; median wall ms; every proof verified (gnark VK / snarkjs VK).

| K | gnark CPU (ref, all cores) | **gnark v0.16.3 + icicle-gnark v3.2.2** (`icicleGroth.Prove`, PK not pinned) | same, `WithPinKeysToGPU` | **ICICLE-SNARK bf00385** (`--device CUDA`, zkey cached) | ICICLE-SNARK cold (1st prove, zkey parse + H2D) |
|---|---|---|---|---|---|
| 10 | 3.6 | 26.5 (5) | 26.1 (5) | 19.7 (5) | 134.7 |
| 14 | 19.0 | 31.2 (5) | 30.1 (5) | 21.3 (5) | 26.1 |
| 18 | 189.4 | **48.3** (3) | 44.4 (3) | **41.3** (5) | 73.1 |
| 20 | 665.7 | **203.2** (3) | 180.6 (3) | **114.3** (5) | 232.9 |

- gnark+ICICLE time = gnark constraint solver (`solve_ms` 0.2 / 1.5 / 9.7 / 40.6 ms — CPU) + H2D of witness-dependent vectors + GPU MSMs/NTTs + proof D2H; PK vectors are re-uploaded each proof unless pinned. Speed-up vs gnark CPU on this box: K=18 3.9× (4.3× pinned), K=20 3.3× (3.7× pinned); K≤14 is *slower* than CPU (≈26 ms fixed launch/transfer floor). Admission gate passed: build with `-DCUDA_ARCH=120` on CUDA 12.8, valid verified proofs at all K. First prove of a process includes ICICLE backend load + device warm-up (`first_prove_ms` 289 ms at K=10).
- ICICLE-SNARK: worker's own `proof took` timer; includes reading `witness.wtns` from disk (32 MB at K=20) and writing proof/public JSON, excludes zkey parsing (cached). Driver-side wall agrees within 0.1 ms. No witness solving (Circom wtns pre-generated) — so vs gnark+ICICLE subtract ~41 ms of solver at K=20 for a like-for-like view. Experimental per upstream README.
- Files: `bench/box-gpu-gnark-icicle.json`, `bench/box-gpu-gnark-icicle-pinned.json`, `bench/box-gpu-icicle-snark.json`.

## Results — RTX 5090 primitives (BN254 G1 MSM, Fr radix-2 NTT; median of 10 after 1 warm-up)

| 2^k | ICICLE v4 MSM device-resident (kernel only) | ICICLE v4 MSM host scalars (H2D scalars, cached bases) | sppark v0.1.15 MSM `multi_scalar_mult_arkworks` (H2D points+scalars each call) | ICICLE v4 NTT fwd device in-place | ICICLE v4 NTT fwd host in/out | sppark NTT fwd host in-place (H2D+D2H) |
|---|---|---|---|---|---|---|
| 10 | 2.28 | 2.91 | 1.91 | 0.025 | 0.193 | 0.029 |
| 12 | 2.61 | 3.17 | 2.05 | 0.025 | 0.144 | 0.038 |
| 14 | 2.84 | 3.68 | 3.04 | 0.030 | 0.193 | 0.093 |
| 16 | 2.78 | 3.80 | 7.91 | 0.055 | 0.317 | 0.217 |
| 18 | 3.55 | 4.83 | 24.7 | 0.140 | 0.739 | 0.689 |
| 19 | 4.83 | 5.20 | 47.2 | 0.249 | 1.373 | 1.335 |
| 20 | **7.17** | 7.39 | 92.0 | **0.622** | 2.96 | 2.63 |

- ICICLE (open-icicle v4.0.0, `-DCUDA_ARCH=120`, our `comparators/gpu/icicle-prim`): synchronous calls (`is_async=false`), precompute factor 1, `c` auto, batch 1; device result == host-path result at every size; NTT round-trip `ifft(fft(x)) == x` at every size; twiddle domain for 2^20 initialised once (1.1 ms, untimed). MSM has a ≈2.3 ms floor below 2^17 (kernel-launch/bucket setup bound). ICICLE's stock criterion benches were not used (their timer is async with sync outside the loop).
- sppark MSM is the shipped `poc/msm-cuda` criterion bench (`BENCH_NPOW=k`, `--features bn254`; sm_120 selected by sppark's nvcc probe); its API takes host arkworks 0.3 slices and copies points **and** scalars every call, so it is host-inclusive and not comparable to the device-resident ICICLE column (2^20: 64 MB points + 32 MB scalars per call). sppark ships no BN254 NTT timing bench; `comparators/gpu/sppark/ntt_timer.rs` times `ntt_cuda::NTT/iNTT` (host in-place, round-trip checked).
- File: `bench/box-gpu-primitives.json` (`icicle.*`, `sppark.*`, per-size samples).

## Bend 2 on the box (for the Bend-CUDA lane)

- Installed with `curl -fsSL https://bend-lang.com/install.sh | BEND_NO_TELEMETRY=1 sh` → `/root/.bend` (`/root/.bend/bin/bend` → `app/2.0.5/…`; installs bun into `/root/.bun`). `bend --version` = **bend 2.0.5**. PATH: `export PATH=/root/.bend/bin:/root/.bun/bin:/usr/local/cuda/bin:$PATH` (only added to `.bashrc`).
- CLI: `bend file.bend` = check + run (interpreter, 74 ms for hello); `bend file.bend -o out` = native binary; `-o out.c` emits one C file.
- C target: `bend hello.bend -o hello` → 1.1 MB static-ish binary (libc/libm only), prints. 0.3 s build.
- CUDA target: a program using `!` (`pow2!(20n)`) needs **clang ≥ 19** — stock Ubuntu clang 18 is rejected ("bend needs clang 19"). Installed `clang-19` via `bash llvm.sh 19` (apt.llvm.org). Then `bend pow2.bend -o pow2` builds in 0.76 s, prints 1048576, links `libcuda.so.1` + `libnvrtc.so.12` (kernels are NVRTC-JIT'd at run time; emitted C contains `__global__ void bend_dev(...)`). Run 0.12 s.
- Smoke script: `comparators/box/bend-smoke.sh`; files in `/root/bendtest/`.

## Cost / time

Started 05:47 UTC; all comparator runs done 07:00 UTC (~1.3 h ≈ $0.8 of the $40 budget at $0.628/h). Box left running for the Bend-CUDA lane.
