# comparators/box — CUDA-box comparator runs

Everything here runs on the RTX 5090 box described in [`docs/box.md`](../../docs/box.md); the numbers land in
`bench/box-*.json` and are tabulated in `docs/box.md` / `docs/benchmarks.md`.

Paths come from environment variables (defaults in parentheses): `REPO` (this checkout), `DEV` (`/root/dev`, pinned
comparator sources), `ART` (`/root/art`, builds + artifacts), `TOOLS` (`/root/tools`, circom + snarkjs).

## One-time setup (Ubuntu 24.04, CUDA 12.8 devel image)

```sh
apt-get install -y build-essential clang cmake libgmp-dev libsodium-dev nasm curl m4 pkg-config git jq time
curl -fsSL https://go.dev/dl/go1.25.7.linux-amd64.tar.gz | tar -C /usr/local -xz          # Go 1.25.7 (gnark v0.16.3 go.mod)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs     # Node 22
curl https://sh.rustup.rs -sSf | sh -s -- -y                                              # Rust (1.95 used)
DEV=${DEV:-/root/dev}; ART=${ART:-/root/art}; TOOLS=${TOOLS:-/root/tools}
mkdir -p $DEV $TOOLS $ART && cd $DEV
npm install --prefix $TOOLS snarkjs@0.7.6
curl -fsSL https://github.com/iden3/circom/releases/download/v2.2.3/circom-linux-amd64 -o $TOOLS/circom && chmod +x $TOOLS/circom
git clone --branch v0.0.8 --recurse-submodules https://github.com/iden3/rapidsnark
git clone --branch v3.2.2 https://github.com/ingonyama-zk/icicle-gnark
git clone https://github.com/ingonyama-zk/icicle-snark && git -C icicle-snark checkout bf00385db19087a8a3f6d754b43b006254b1b465
git clone --branch v4.0.0 https://github.com/ingonyama-zk/open-icicle
git clone --branch v0.1.15 --recurse-submodules https://github.com/supranational/sppark
git clone https://github.com/0xAndoroid/bend-groth16                                      # REPO
```

`comparators/gpu/icicle-prim/Cargo.toml` reaches `open-icicle` through the gitignored symlink `comparators/gpu/icicle-prim/open-icicle` (`build.sh` creates it: `ln -sfn $DEV/open-icicle comparators/gpu/icicle-prim/open-icicle`).

## Artifacts and builds

- `gen-all.sh` → `circom/gen.sh K $ART`: compiles `SquareChain(2^K)` (template = the frozen circuit; the two
  linear aliases are removed by circom's default `--O1`, leaving exactly 2^K constraints — checked against
  `snarkjs r1cs info`), makes the witness for `x0 = 3`, downloads the PSE `ppot_0080_{K+1}.ptau`, runs
  `snarkjs groth16 setup`, exports `vk.json`. Artifacts are shared by rapidsnark, snarkjs and ICICLE-SNARK.
- `build.sh`: rapidsnark (`build_gmp.sh host && make host`), icicle-gnark v3.2.2 CUDA backend for all four curves
  (`-DCUDA_ARCH=120`; gnark's `icicle` build tag links every curve), the Go runner (CPU + `-tags=icicle`),
  ICICLE-SNARK (vendored icicle, `-DCUDA_BACKEND=local -DCUDA_ARCH=120`, `cargo build --release`), open-icicle v4.0.0
  bn254 + local CUDA backend into its own prefix, the `icicle-prim` crate, sppark's `poc/msm-cuda` bench and the
  `ntt_timer` example.

## Runs

- `run-cpu.sh` → `bench/box-cpu-gnark.json` (+ `-1thread`), `box-cpu-rapidsnark.json`, `box-cpu-snarkjs.json`
- `../gpu/run-gpu.sh` → `bench/box-gpu-gnark-icicle.json` (+ `-pinned`), `box-gpu-icicle-snark.json`, `box-gpu-primitives.json`
- `bend-smoke.sh` — Bend 2 interpreter / C / CUDA `!` smoke test; `bend-cuda.sh` — Bend 2 field/G1 primitive benches on CUDA
  (`bend2/bench/box_results.md`)

Each JSON follows `bench/README.md` schema 1 (`prove.<K>.{ms, iters, samples_ms, verified, …}`); `notes` states
exactly what each timer includes (witness solving, file I/O, H2D). Run one prover at a time on an otherwise idle box.
