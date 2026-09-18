# circom / snarkjs / rapidsnark comparator

Groth16 over BN254 on the canonical `SquareChain(N)` circuit (private `x0`,
`x_{i+1} = x_i * x_i`, public output `y = x_N`), N = 2^K for K ∈ {10, 14, 18, 20}.
Constraint count is **exactly N** at every K (`snarkjs r1cs info`): the N
quadratic constraints survive, the two linear aliases (`x[0] <== x0`,
`y <== x[N]`) are removed by circom's default linear-constraint simplification
(`--O1`, the default in circom 2.2.x). No template adjustment was needed.

| K  | constraints | wires     | r1cs      | zkey    | setup wall (snarkjs) | ptau used      |
|----|-------------|-----------|-----------|---------|----------------------|----------------|
| 10 | 1,024       | 1,026     | 33 KB     | 0.55 MB | <1 s                 | ppot_0080_11   |
| 14 | 16,384      | 16,386    | 0.5 MB    | 8.8 MB  | 29 s                 | ppot_0080_15   |
| 18 | 262,144     | 262,146   | 8.4 MB    | 140 MB  | 72 s (RSS 1.3 GB)    | ppot_0080_19   |
| 20 | 1,048,576   | 1,048,578 | 33.5 MB   | 562 MB  | 264 s (RSS 2.8 GB)   | ppot_0080_21   |

`nConstraints + nOutputs + nPubInputs = 2^K + 1` rounds up to the radix-2 domain 2^(K+1) = 2N,
so the ptau must have power ≥ K+1.

## Files

- `square_chain.circom` — parameterised template (FROZEN circuit).
- `gen.sh K [OUT_DIR]` — writes `square_chain_K.circom` (`component main = SquareChain(2^K)`),
  runs `circom --r1cs --wasm --sym`, prints `snarkjs r1cs info`.
- `bench.py` — times `groth16 prove` for snarkjs or rapidsnark, verifies every proof
  with `snarkjs groth16 verify`, writes the `bench/*.json` schema.
- Results: `bench/snarkjs-macmini.json`, `bench/rapidsnark-macmini.json`.

## Versions (Mac mini, Apple M4, 10 cores, 16 GB, macOS 26)

- circom 2.2.3 — release asset `circom-macos-amd64` from
  <https://github.com/iden3/circom/releases/tag/v2.2.3> (despite the name it is a
  native `Mach-O arm64` binary; no Rust build needed).
- snarkjs 0.7.6 (`npm i snarkjs` into a scratch dir), Node v26.8.2.
- rapidsnark `81eddf1a536d26497b237c0b8a04fe90baf7e439` (2026-09-18 main), built for
  `macos_arm64` with Xcode clang; gmp 6.3 built by its `build_gmp.sh macos_arm64`.
  Brew deps: `cmake gmp libsodium nasm`.
- Powers of tau: PSE Perpetual Powers of Tau, contribution 80, phase-2-prepared —
  `https://pse-trusted-setup-ppot.s3.eu-central-1.amazonaws.com/pot28_0080/ppot_0080_XX.ptau`
  (XX = 11, 15, 19, 21; 2.4 MB / 38 MB / 604 MB / 2.4 GB). **Gotcha:** the Hermez
  files listed in the snarkjs README (`storage.googleapis.com/zkevm/ptau/...` and
  `hermez.s3-eu-west-1.amazonaws.com`) return 403 as of 2026-09-18.

## Artifacts (outside the repo, gitignored patterns `*.ptau *.zkey *.wtns`)

All under `$TMPDIR/bend-groth16/w0e/` on the Mac mini (`$TMPDIR=/Volumes/Dev/tmp`):

- `bin/circom`, `snarkjs/node_modules/.bin/snarkjs`
- `ptau/ppot_0080_{11,15,19,21}.ptau`
- `build/square_chain_K/` — `.circom`, `.r1cs`, `.sym`, `square_chain_K_js/*.wasm`
- `zkey/square_chain_K.zkey`, `zkey/square_chain_K.vkey.json`, `zkey/setup_K.log`
- `wtns/square_chain_K.wtns` — witness for `input.json = {"x0":"12345678901234567890"}`
- `rapidsnark/src/package_macos_arm64/bin/prover`

## Exact commands

```sh
L=$TMPDIR/bend-groth16/w0e; export PATH=$L/bin:$L/snarkjs/node_modules/.bin:$PATH
# 1. compile (K=10 shown)
comparators/circom/gen.sh 10 $L/build            # prints "# of Constraints: 1024"
# 2. setup + vkey (12 GB heap needed for K=20: use node --max-old-space-size=12000 .../snarkjs/build/cli.cjs)
snarkjs groth16 setup $L/build/square_chain_10/square_chain_10.r1cs $L/ptau/ppot_0080_11.ptau $L/zkey/square_chain_10.zkey
snarkjs zkey export verificationkey $L/zkey/square_chain_10.zkey $L/zkey/square_chain_10.vkey.json
# 3. witness
echo '{"x0":"12345678901234567890"}' > $L/input.json
snarkjs wtns calculate $L/build/square_chain_10/square_chain_10_js/square_chain_10.wasm $L/input.json $L/wtns/square_chain_10.wtns
# 4. prove + verify (snarkjs)
snarkjs groth16 prove $L/zkey/square_chain_10.zkey $L/wtns/square_chain_10.wtns proof.json public.json
snarkjs groth16 verify $L/zkey/square_chain_10.vkey.json public.json proof.json   # -> OK!
# 5. rapidsnark build + prove
git clone --recursive https://github.com/iden3/rapidsnark $L/rapidsnark/src && cd $L/rapidsnark/src
./build_gmp.sh macos_arm64
mkdir build_prover_macos_arm64 && cd build_prover_macos_arm64 && \
  cmake .. -DTARGET_PLATFORM=macos_arm64 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=../package_macos_arm64 && \
  make -j8 && make install
$L/rapidsnark/src/package_macos_arm64/bin/prover $L/zkey/square_chain_10.zkey $L/wtns/square_chain_10.wtns proof.json public.json
# 6. benchmark (verifies every proof)
export BENCH_DIR=$L SNARKJS=$L/snarkjs/node_modules/.bin/snarkjs RAPIDSNARK=$L/rapidsnark/src/package_macos_arm64/bin/prover
uv run python comparators/circom/bench.py --prover rapidsnark --ks 10 14 18 20 --runs 5 --version "rapidsnark <sha>" --out bench/rapidsnark-macmini.json
uv run python comparators/circom/bench.py --prover snarkjs    --ks 10 14 18 20 --runs 3 --version "snarkjs 0.7.6, node v26.8.2" --out bench/snarkjs-macmini.json
```

`make macos_arm64` from the rapidsnark Makefile uses `$(nproc)`, which does not exist
on macOS — the cmake/make lines above are what the Makefile target runs, with `-j8`.

## Results (median wall ms of `groth16 prove`, proof verified each run)

| K  | constraints | rapidsnark (10 threads) | snarkjs (node) |
|----|-------------|-------------------------|----------------|
| 10 | 1,024       | 20.8                | 401.6          |
| 14 | 16,384      | 150.7               | 1,419.1        |
| 18 | 262,144     | 2,722.6             | 18,424.6       |
| 20 | 1,048,576   | 9,792.3             | 59,408.4       |

Notes:
- Wall time includes process start and reading the zkey from disk (562 MB at K=20),
  as any CLI user would experience it. Public output `y` is identical for both provers
  (`1334343819814275311873148782430997933860619058220351324399995139625215999052`).
- rapidsnark thread count = `std::thread::hardware_concurrency()` (10 here), derived at
  runtime by ffiasm's `ThreadPool::defaultPool()`; there is no CLI flag or env var to
  pin it to 1 thread, and macOS has no `taskset`, so no 1-thread number is recorded.
- snarkjs prove is JS + wasm (ffjavascript) using web-worker threads (`os.cpus().length`).
