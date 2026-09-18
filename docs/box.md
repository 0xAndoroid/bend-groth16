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
