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
