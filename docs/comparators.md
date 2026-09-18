# Groth16 comparator selection — BN254

Checked **2026-09-18** against GitHub APIs, pinned source, package registries, and operator/vendor documentation. This is a research plan: install commands and benchmark sketches below were source-checked, not executed on either target. No performance ranking is established yet.

## Recommended set

1. **CPU: gnark v0.16.3, all available cores.** First production baseline: maintained Go implementation, native BN254, parallel MSM/FFT. [Celer and Linea are named users](https://github.com/Consensys/gnark/blob/v0.16.3/docs/KNOWN_USERS.md), and [Brevis documents the gnark Groth16/ICICLE family](https://www.ingonyama.com/oldblogs/icicle-case-study-accelerating-zk-proofs-with-brevis) (2024-08-27); Linea's use of gnark is **not** evidence that Linea currently runs Groth16.
2. **CPU: rapidsnark v0.0.8.** Production identity-stack baseline: [Privado ID's issuer imports its prover](https://github.com/0xPolygonID/issuer-node/blob/main/go.mod), and the same Circom key/witness can run unchanged in snarkjs and ICICLE-SNARK. Native ARM/x86 field assembly and a C++ thread pool make this a useful independent CPU implementation.
3. **GPU: gnark v0.16.3 + icicle-gnark v3.2.2.** Primary production-family comparison: Brevis's cited deployment actually used gnark Groth16 with ICICLE, not merely unrelated GPU primitives. The selected upstream [integration remains experimental](https://github.com/Consensys/gnark/blob/v0.16.3/backend/accelerated/icicle/doc.go); the deployment citation does not certify these exact pins or RTX 5090.
4. **GPU: ICICLE-SNARK at bf00385, supplementary.** Direct `.zkey`/`.wtns` compatibility gives the cleanest Circom end-to-end comparison. Its [README explicitly excludes production use](https://github.com/ingonyama-zk/icicle-snark/tree/bf00385db19087a8a3f6d754b43b006254b1b465), so label it experimental, not a second verified production deployment.

Keep snarkjs and arkworks as references. Do not force a third production CPU slot: bellman-ce is archived; stock bellperson/SupraSeal is the wrong curve. Report sppark **BN254 primitives**, not an invented sppark BN254 Groth16 prover.

## Version and maintenance ledger

Dates are UTC publication dates; `tag` means no matching GitHub release, `crate` means crates.io publication. Last commit means default-branch tip at inspection, not repository `pushed_at`. All links accessed 2026-09-18.

| Candidate | Latest version / publication | Last commit / status |
|---|---|---|
| gnark | [v0.16.3](https://github.com/Consensys/gnark/releases/tag/v0.16.3), 2026-08-24 | [572187f](https://github.com/Consensys/gnark/commit/572187f0ca25819472b6993812c32991f42c00ae), 2026-09-15; active |
| gnark-crypto | [v0.21.0](https://github.com/Consensys/gnark-crypto/releases/tag/v0.21.0), 2026-08-10; gnark's pinned dependency | [9c53d21](https://github.com/Consensys/gnark-crypto/commit/9c53d21cf2ffe5a851f56c8ce8ea3fbf086e2357), 2026-09-15; active |
| rapidsnark | [v0.0.8](https://github.com/iden3/rapidsnark/releases/tag/v0.0.8), 2026-01-07 | [81eddf1](https://github.com/iden3/rapidsnark/commit/81eddf1a536d26497b237c0b8a04fe90baf7e439), 2026-04-16; unarchived |
| bellperson | [0.27.0 crate](https://crates.io/crates/bellperson/0.27.0), 2026-02-26; tag v0.27.0, no GitHub releases | [a215065](https://github.com/filecoin-project/bellperson/commit/a2150655c91148db04f04b60918be7912836a5d5), 2026-09-01; active |
| bellman-ce | [0.8.0 crate](https://crates.io/crates/bellman_ce/0.8.0), 2024-07-05; tag crates.io-v0.8.0 | [26ed417](https://github.com/matter-labs/bellman/commit/26ed417cf7b4ec2a4be6706cdef596144cda2264), 2024-08-15; **archived**; old GitHub release 0.3.1 is not latest crate |
| snarkjs | [v0.7.6](https://github.com/iden3/snarkjs/releases/tag/v0.7.6), 2026-01-26 | [9a8f1c0](https://github.com/iden3/snarkjs/commit/9a8f1c0083d18b9b5e18f526cfd729e7259423be), 2026-01-12; unarchived |
| ark-groth16 | [0.6.0 crate](https://crates.io/crates/ark-groth16/0.6.0), 2026-04-26; tag v0.6.0 | [8f0904a](https://github.com/arkworks-rs/groth16/commit/8f0904a7d7a2c8945bf770bdd3c2081e0be1941a), 2026-08-02; active; GitHub's v0.3.0 release is stale |
| ICICLE | [v4.0.0](https://github.com/ingonyama-zk/icicle/releases/tag/v4.0.0), 2025-07-11 | [625532a](https://github.com/ingonyama-zk/icicle/commit/625532a624e5aaa6e9d31a1c92587f1fcc30dc76), 2025-08-06; public tree unchanged since then |
| open-icicle | [v4.0.0](https://github.com/ingonyama-zk/open-icicle/releases/tag/v4.0.0), 2026-06-03; distinct repository | [a1f8a74](https://github.com/ingonyama-zk/open-icicle/commit/a1f8a74b4c604367b9e1eae41aca4d02687e96fc), 2026-06-25; use this source-available CUDA tree for v4 primitives |
| icicle-gnark | [v3.2.2 tag](https://github.com/ingonyama-zk/icicle-gnark/tree/v3.2.2), tag commit 2024-12-23; no GitHub releases | [1a967ec](https://github.com/ingonyama-zk/icicle-gnark/commit/1a967ecde705f1e5e841b10dee96064e2190547e), 2025-04-24; still pinned by gnark v0.16.3 |
| ICICLE-SNARK | No tags/releases; Cargo manifest 0.1.0; pin [bf00385](https://github.com/ingonyama-zk/icicle-snark/commit/bf00385db19087a8a3f6d754b43b006254b1b465), 2025-07-09 | Same last commit; unarchived, no subsequent public commits |
| sppark | [0.1.15 crate](https://crates.io/crates/sppark/0.1.15), 2026-06-04; tag v0.1.15, no GitHub releases | [17278d7](https://github.com/supranational/sppark/commit/17278d74295392f9813f009300b257a688422b7a), 2026-06-04; maintained |
| SupraSeal / supraseal-c2 | [0.1.2 crate](https://crates.io/crates/supraseal-c2/0.1.2), 2025-09-05; tag v0.1.2 | [1d10557](https://github.com/supranational/supra_seal/commit/1d1055700f91b98f89a00ec620412211d3b00908), 2025-09-05; deployed Filecoin path, unarchived |
| cuZK research artifact | No tags/releases; pin [88e3295](https://github.com/Tao-Lu-123/cuZK/commit/88e3295cada379abe06240df23ec6c9fc0f648b2), 2023-04-13 | Same last commit; dormant research code |
| era-bellman-cuda | [prerelease-dev-d1fa867](https://github.com/matter-labs/era-bellman-cuda/releases/tag/prerelease-dev-d1fa867), 2026-04-23 | [d1fa867](https://github.com/matter-labs/era-bellman-cuda/commit/d1fa8670ee84ec3477c6cc1c85a3554cfa5e0206), 2026-04-23; unarchived, prerelease |
| Zeknox | [v1.0.1-zeknox_p2](https://github.com/okx/zeknox/releases/tag/v1.0.1-zeknox_p2), 2025-02-07; v1.0.1 published the same day | [0ff6aee](https://github.com/okx/zeknox/commit/0ff6aeed66007b010f4c52119f81408635648bfb), 2025-02-07; unarchived, public activity stale |

Recheck evidence, substituting any repository above; releases, tags, and package publication are separate facts:

```sh
gh release list -R Consensys/gnark --limit 3 --json tagName,publishedAt,isPrerelease
gh api 'repos/Consensys/gnark/commits?per_page=1' --jq '.[0]|{sha,date:.commit.committer.date}'
gh api repos/filecoin-project/bellperson/tags --jq '.[0:3]|map(.name)'
curl -fsSL https://crates.io/api/v1/crates/bellperson/0.27.0 | jq '.version|{num,created_at}'
```

## Production, formats, and hardware fit

“Mac CPU” below is source/platform support, not a completed build in this lane. No CUDA runs on Apple Silicon. Linux means x86_64; CUDA rows require the separate Blackwell gate below.

| Candidate | Deployment evidence and BN254 | Circuit input / parallelism | macOS arm64 / Ubuntu 24.04 + RTX 5090 |
|---|---|---|---|
| gnark | Celer, Brevis; Linea uses gnark but [switched its outer proof to PLONK](https://linea.build/blog/the-linea-prover-for-a-very-smart-high-schooler). BN254 supported. | Go frontend → R1CS; low-level constraint API permits matrix import, no stock Circom file importer. Goroutines / gnark-crypto; `GOMAXPROCS`. | Native CPU both; GPU via selected ICICLE integration on Linux. |
| rapidsnark | Privado ID issuer and mobile [c-polygonid](https://github.com/0xPolygonID/c-polygonid/blob/main/go.mod). BN254 (`alt_bn128`). | Circom `.zkey` + `.wtns`; `.r1cs` consumed by setup, not prover. [ThreadPool](https://github.com/iden3/rapidsnark/blob/v0.0.8/src/groth16.cpp), assembly, Linux OpenMP. | [Native macos_arm64 recipe](https://github.com/iden3/rapidsnark/tree/v0.0.8); CPU on Linux. Mac CMake disables OpenMP, **not** the thread pool. No CUDA. |
| bellperson | Filecoin storage proofs; [Lotus documents ec-gpu versus SupraSeal](https://github.com/filecoin-project/lotus/issues/13634) (2026-05-23). **No ready BN254 backend** in stock package; shipped GPU kernels are BLS12-381. | Rust `Circuit` / `ConstraintSystem`; own parameter encoding. Rayon CPU; `cuda`/`opencl` use ec-gpu; `cuda-supraseal` is a separate sppark path. | CPU on Mac; no claimed Apple GPU path. Linux CUDA/OpenCL; ec-gpu defaults do not target sm_120: rebuild below. |
| bellman-ce | Matter Labs/zkSync-era lineage; [README now focuses on PLONK](https://github.com/matter-labs/bellman/tree/crates.io-v0.8.0). No current Groth16 operator established. BN254 via `pairing_ce::bn256`. | Rust `Circuit<E>`; Groth16 module still exists. Own parameters; `multicore` feature. | Portable CPU expected on both, omit `asm` on ARM; no CUDA feature in this crate. Historical extra, not headline production baseline. |
| snarkjs | [Privado ID JS SDK calls `groth16.prove`](https://github.com/0xPolygonID/js-sdk/blob/main/src/proof/provers/prover.ts). BN254 supported. | Circom `.r1cs` setup, `.zkey` + `.wtns` proving; Node/WASM workers. | CPU on both; no CUDA. Reference baseline only. |
| ark-groth16 | BN254 supported; upstream [labels itself an unaudited prototype](https://github.com/arkworks-rs/groth16/tree/v0.6.0). No specific production prover deployment established here. | Rust `ConstraintSynthesizer`; matrices/import adapter possible, no native Circom CLI. Rayon `parallel` feature. | CPU on both; no upstream CUDA backend. Correctness/reference data point. |
| ICICLE / ICICLE-SNARK | ICICLE's Brevis deployment is cited above; **not evidence of ICICLE-SNARK deployment**. Both support BN254. | ICICLE APIs consume points/scalars; **ICICLE-SNARK consumes Circom zkey/wtns**, with CPU/CUDA and key cache. No end-to-end Groth16 example in inspected ICICLE v4 tree. | ARM CPU backend; public pins do not provide a ready Apple Metal prover. Linux CUDA source can target 120; runtime verification pending. |
| sppark / SupraSeal | Filecoin C2/WindowPoSt via bellperson + `supraseal-c2`; [sppark has BN254 MSM/NTT PoCs](https://github.com/supranational/sppark/tree/v0.1.15/poc). [SupraSeal C2 hardcodes BLS12-381](https://github.com/supranational/supra_seal/blob/v0.1.2/c2/build.rs), not a BN254 zkey prover. | sppark = primitive templates; C2 consumes bellperson assignments/parameters. ec-gpu and sppark are distinct backends. | Mac has non-GPU components only; GPU benches Linux. v0.1.15 explicitly generates sm_120 when nvcc supports it. |
| cuZK | [TCHES research artifact](https://github.com/Tao-Lu-123/cuZK); Filecoin evaluation ≠ production deployment. ALT_BN128 and BLS12-381 examples. | C++/CUDA-generated R1CS examples; no Circom importer. GPU end-to-end research implementation. | No Mac CUDA; documented CUDA 11.5/V100 stack, Makefile hardcodes `sm_35`: **fails unchanged with CUDA 12.8**. Exclude pending a separate port. |
| era-bellman-cuda | [zkSync prover acceleration library](https://github.com/matter-labs/era-bellman-cuda/tree/d1fa8670ee84ec3477c6cc1c85a3554cfa5e0206); BN254 MSM/NTT, not proof of production Groth16 use. | Device arrays / C ABI primitives; no ready Groth16 R1CS/zkey entry point. | No Mac GPU; Linux, default arch 80. Override `-DCMAKE_CUDA_ARCHITECTURES=120`; no claimed 5090 validation. |
| Zeknox | [OKX Plonky2 / proof-of-reserves integration](https://github.com/okx/zeknox/tree/v1.0.1); experimental `okx/gnark` branch for Groth16 MSM. BN254 MSM; stock NTT is **Goldilocks**, not BN254 Fr. | Primitive API; Groth16 needs gnark fork, not `.zkey`. No verified production deployment of that Groth16 fork. | CUDA/Linux; no Mac GPU; no advertised sm_120 validation. Not selected. |

## Same-R1CS contract

For every `N ∈ {1024, 16384, 262144, 1048576}`, use BN254 **Fr**, private `x0 = 3`, `x[i+1] = x[i]^2`, public `y = x[N]`. Canonical witness order: `[1, y, x0, x1, …, x[N-1]]`; **N rows, N+2 wires, one public scalar**. Intermediates are auxiliary witness values, not extra public inputs.

Before timing, export each frontend's rows, rename wires to that order, normalize each single-term A/B coefficient to one (adjust C by their product), and compare the ordered `(A,B,C)` tuples/hash to the Circom artifact. Check all rows, not just equal counts. Share identical `.r1cs`, `.wtns`, `.zkey` across rapidsnark/snarkjs/ICICLE-SNARK; gnark gets the same normalized rows but its own setup/key encoding. Setup and witness construction are outside prove-only timing.

**Record QAP domain separately:** [gnark uses `next_pow2(N)`](https://github.com/Consensys/gnark/blob/v0.16.3/backend/groth16/bn254/setup.go); [snarkjs adds public/constant rows](https://github.com/iden3/snarkjs/blob/v0.7.6/src/zkey_new.js), so its domain is `next_pow2(N+2) = 2N`. This backend difference is real; do not pad the logical circuit or call domain length the constraint count.

### Circom → rapidsnark, snarkjs, ICICLE-SNARK

Pin [Circom v2.2.3](https://github.com/iden3/circom/releases/tag/v2.2.3) (2025-10-27), snarkjs v0.7.6. Save this template as `SquareChain.circom`; all selected N are at least two:

```circom
pragma circom 2.2.3;
template SquareChain(N) {
    signal input x0;
    signal output y;
    signal step[N-1];
    step[0] <== x0 * x0;
    for (var i = 1; i < N-1; i++) step[i] <== step[i-1] * step[i-1];
    y <== step[N-2] * step[N-2];
}
component main = SquareChain(1024);
```

Hermez files: requested [power 18](https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_18.ptau), [power 20](https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_20.ptau); **these are too small for exactly 2^18 / 2^20 rows plus the public output**. Use [power 19](https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_19.ptau) / [power 21](https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_21.ptau), respectively; small cases need powers 11/15. Verify downloaded Blake2b hashes against [snarkjs's published table](https://github.com/iden3/snarkjs/blob/v0.7.6/README.md#7-prepare-phase-2).

Run in an asset directory under `$TMPDIR`; `snarkjs` and `circom` are the pinned executables installed below. These circuit-specific setup keys are for benchmarking only, without a production phase-2 ceremony.

```sh
for k in 10 14 18 20; do
  n=$((1 << k)); p=$((k + 1)); d="square-$k"
  mkdir -p "$d"
  sed "s/SquareChain(1024)/SquareChain($n)/" SquareChain.circom > "$d/circuit.circom"
  circom "$d/circuit.circom" --r1cs --wasm --sym --O0 --prime bn128 -o "$d"
  snarkjs r1cs info "$d/circuit.r1cs"
  printf '{"x0":"3"}\n' > "$d/input.json"
  node "$d/circuit_js/generate_witness.js" "$d/circuit_js/circuit.wasm" "$d/input.json" "$d/witness.wtns"
  snarkjs wtns check "$d/circuit.r1cs" "$d/witness.wtns"
  curl -fL "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_$p.ptau" -o "pot$p.ptau"
  snarkjs groth16 setup "$d/circuit.r1cs" "pot$p.ptau" "$d/circuit.zkey"
  snarkjs zkey export verificationkey "$d/circuit.zkey" "$d/vk.json"
  snarkjs groth16 prove "$d/circuit.zkey" "$d/witness.wtns" "$d/proof.json" "$d/public.json"
  snarkjs groth16 verify "$d/vk.json" "$d/public.json" "$d/proof.json"
done
```

For rapidsnark replace only the `groth16 prove` invocation with `"$RAPID_PROVER" "$d/circuit.zkey" "$d/witness.wtns" "$d/proof.json" "$d/public.json"`; verify with snarkjs afterward. Measure executable wall time as **cold/file-inclusive**. Warm prove-only needs a small caller around the library's in-memory prover, not repeated CLI launches.

### gnark frontend and timer

Imports: `frontend`, `frontend/cs/r1cs`, `constraint`, `backend/groth16` under `github.com/consensys/gnark`; `ecc` under `github.com/consensys/gnark-crypto`; standard `math/big`, `time`. `check(err)` below means abort on non-nil error. The final row uses the existing [generic R1C blueprint](https://github.com/Consensys/gnark/blob/v0.16.3/constraint/blueprint_r1cs.go), because `AssertIsEqual(Mul(x,x),Y)` would emit **two** rows.

```go
type SquareChain struct {
    X0 frontend.Variable
    Y frontend.Variable `gnark:",public"`
    N int `gnark:"-"`
}
func (c *SquareChain) Define(api frontend.API) error {
    x := c.X0
    for i := 0; i < c.N-1; i++ { x = api.Mul(x, x) }
    cp := api.Compiler()
    bp := &constraint.BlueprintGenericR1C{}
    id := cp.AddBlueprint(bp)
    a := cp.ToCanonicalVariable(x).(constraint.LinearExpression)
    out := cp.ToCanonicalVariable(c.Y).(constraint.LinearExpression)
    var data []uint32
    bp.CompressR1C(&constraint.R1C{L: a, R: a, O: out}, &data)
    cp.AddInstruction(id, data)
    return nil
}
ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &SquareChain{N:n}); check(err)
if ccs.GetNbConstraints() != n { panic("constraint count") }
pk, vk, err := groth16.Setup(ccs); check(err)
y := big.NewInt(3)
for i := 0; i < n; i++ { y.Mul(y,y).Mod(y,ecc.BN254.ScalarField()) }
w, err := frontend.NewWitness(&SquareChain{X0:3,Y:y,N:n}, ecc.BN254.ScalarField()); check(err)
t := time.Now(); proof, err := groth16.Prove(ccs,pk,w); elapsed := time.Since(t); check(err)
pub, err := w.Public(); check(err); check(groth16.Verify(proof,vk,pub))
```

Run the host sketch for all four N; warm once, retain keys, then collect ten proofs. Set `GOMAXPROCS=1` and separately `GOMAXPROCS=$THREADS`; unset uses Go's runtime default. Time includes gnark's solver; record a separate solve time if comparing against already-expanded Circom witnesses. CPU binary has no `icicle` build tag.

### Bellperson circuit / curve exclusion

This emits N rows with `bellperson::{Circuit,ConstraintSystem,SynthesisError}` and `ff::PrimeField`; assignments may be `None` during setup. **Stock proving uses `blstrs::Bls12`/`Scalar`, not BN254**: use this only in a separately labelled BLS12-381 appendix. A BN254 pairing engine plus `GpuName`/kernel integration is porting work, not a feature flag.

```rust
struct SquareChain<F> { x0: Option<F>, n: usize }
impl<F: ff::PrimeField> Circuit<F> for SquareChain<F> {
    fn synthesize<CS: ConstraintSystem<F>>(self, cs: &mut CS) -> Result<(), SynthesisError> {
        let mut value = self.x0;
        let mut x = cs.alloc(|| "x0", || value.ok_or(SynthesisError::AssignmentMissing))?;
        for i in 0..self.n {
            let next = value.map(|v| v.square());
            let get = || next.ok_or(SynthesisError::AssignmentMissing);
            let z = if i+1 == self.n { cs.alloc_input(|| "y", get)? }
                    else { cs.alloc(|| format!("x{}", i+1), get)? };
            cs.enforce(|| format!("square{i}"), |lc| lc+x, |lc| lc+x, |lc| lc+z);
            x = z; value = next;
        }
        Ok(())
    }
}
```

Use `generate_random_parameters` outside timing, then `create_random_proof`; verify `[y]`. [Features/build script](https://github.com/filecoin-project/bellperson/blob/v0.27.0/build.rs): CPU `--no-default-features --features groth16`; GPU `--features cuda` or `--features opencl`; sppark `--features cuda-supraseal`, not `cuda`. bellman-ce's `Circuit<Bn256>` uses the analogous `alloc`/`alloc_input`/`enforce` pattern and `--no-default-features --features multicore`; useful optional historical BN254 data, not selected production CPU.

## Installation and GPU recipes

Keep source checkouts under `~/dev/bend-comparators`, artifacts under `$TMPDIR/bend-groth16/comparators`; each ICICLE pin needs its own build/install directory and process. Do not mix v4 primitive libraries with the older Groth16 integrations. All Cargo commands run sequentially.

```sh
DEPS="$HOME/dev/bend-comparators"
TOOLS="$DEPS/tools"
ARTIFACTS="$TMPDIR/bend-groth16/comparators"
mkdir -p "$DEPS" "$TOOLS" "$ARTIFACTS"
npm install --prefix "$TOOLS" snarkjs@0.7.6
export PATH="$TOOLS/bin:$TOOLS/node_modules/.bin:$PATH"
git clone --branch v0.0.8 --recurse-submodules https://github.com/iden3/rapidsnark "$DEPS/rapidsnark"
git clone --branch v3.2.2 https://github.com/ingonyama-zk/icicle-gnark "$DEPS/icicle-gnark"
git clone https://github.com/ingonyama-zk/icicle-snark "$DEPS/icicle-snark"
git -C "$DEPS/icicle-snark" checkout bf00385db19087a8a3f6d754b43b006254b1b465
```

| Host | Dependencies / pins |
|---|---|
| Mac mini | `brew install go rust cmake gmp libsodium nasm node coreutils pkg-config`; Xcode command-line tools required. Set `THREADS=$(sysctl -n hw.logicalcpu)`. No CUDA install or NVIDIA benchmark here. |
| Ubuntu 24.04 CUDA box | Start with CUDA **12.8 devel** image, not runtime-only; working host NVIDIA driver. As root: `apt-get update` then `apt-get install -y build-essential clang cmake libgmp-dev libsodium-dev nasm curl m4 pkg-config git nodejs npm golang-go`; install stable Rust if absent. Set `THREADS=$(nproc)`; log `nvcc --version` and `nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv`. |
| Shared tooling | `GOTOOLCHAIN=go1.25.7 go version`; gnark v0.16.3 [requires Go 1.25.7](https://github.com/Consensys/gnark/blob/v0.16.3/go.mod). In the Go runner: `go get github.com/consensys/gnark@v0.16.3 github.com/consensys/gnark-crypto@v0.21.0`. Install `snarkjs@0.7.6` into a local npm prefix; put its `node_modules/.bin` on PATH. `cargo install --git https://github.com/iden3/circom --tag v2.2.3 circom --root "$TOOLS"`; put `$TOOLS/bin` on PATH. |
| rapidsnark | Clone `iden3/rapidsnark` at `v0.0.8`, initialize submodules. Mac: `./build_gmp.sh macos_arm64` then `make macos_arm64`, executable `package_macos_arm64/bin/prover`. Linux: `./build_gmp.sh host` then `make host`, executable `package/bin/prover`. Set `RAPID_PROVER` to its absolute path. |
| Rust references | Runner dependencies: `ark-groth16 = "=0.6.0"` with `parallel`, matching ark BN254/relations versions; optional `bellman_ce = "=0.8.0"` with `multicore`, or `bellperson = "=0.27.0"`. Native Mac CPU build, no `asm` flag on ARM. Record `Cargo.lock` and `RAYON_NUM_THREADS`. |

### gnark + ICICLE, Linux

Checkout `ingonyama-zk/icicle-gnark` tag `v3.2.2`. In that checkout, set `B="$ARTIFACTS/gnark-build"`, `P="$ARTIFACTS/gnark-install"`; `GNARK_RUNNER` is the separate directory containing the Go sketch's executable harness:

```sh
cmake -S icicle -B "$B" -DCMAKE_BUILD_TYPE=Release -DCURVE=bn254 -DCUDA_BACKEND=ON -DCUDA_ARCH=120 -DCMAKE_INSTALL_PREFIX="$P"
cmake --build "$B" --target install -j "$THREADS"
export CGO_LDFLAGS="-L$P/lib -licicle_device -lstdc++ -lm -Wl,-rpath,$P/lib"
export LD_LIBRARY_PATH="$P/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export ICICLE_BACKEND_INSTALL_DIR="$P/lib/backend"
go -C "$GNARK_RUNNER" build -tags=icicle .
```

Use `icicleGroth "github.com/consensys/gnark/backend/accelerated/icicle/groth16"`, **not the obsolete `backend.WithIcicleAcceleration()` recipe**. Deserialize the native PK into `icicleGroth.NewProvingKey(ecc.BN254)` (`WriteTo`/`ReadFrom` compatible), then time `icicleGroth.Prove(ccs,gpuPK,w)` on the identical gnark rows; verify using the native VK. First call includes device warmup; report it separately. Upstream documents testing CUDA 13/Ubuntu 24.04, **not** CUDA 12.8/5090: build + valid N=1024 proof is an admission gate, not an assumed pass.

### ICICLE-SNARK, Linux; same Circom artifacts

Checkout `ingonyama-zk/icicle-snark` at `bf00385db19087a8a3f6d754b43b006254b1b465`; its vendored ICICLE is the dependency pin, not latest standalone ICICLE. Set `B="$ARTIFACTS/snark-build"`, `P="$ARTIFACTS/snark-install"`, and `d` to an absolute `square-$k` artifact directory. [Build selector](https://github.com/ingonyama-zk/icicle-snark/blob/bf00385db19087a8a3f6d754b43b006254b1b465/icicle/backend/cuda/cmake/Common.cmake) uses `CUDA_ARCH`, so passing only `CMAKE_CUDA_ARCHITECTURES` can be overridden.

```sh
cmake -S icicle -B "$B" -DCMAKE_BUILD_TYPE=Release -DCURVE=bn254 -DCUDA_BACKEND=local -DCUDA_ARCH=120 -DCMAKE_INSTALL_PREFIX="$P"
cmake --build "$B" --target install -j "$THREADS"
export ICICLE_BACKEND_INSTALL_DIR="$P/lib/backend"
export LD_LIBRARY_PATH="$P/lib"
cargo build -q --message-format=short --release
printf 'prove --witness %s/witness.wtns --zkey %s/circuit.zkey --proof %s/proof.json --public %s/public.json --device CUDA\nexit\n' "$d" "$d" "$d" "$d" | target/release/icicle-snark
```

Send eleven `prove` lines followed by `exit` to one worker, separately for each N: first cold, next ten warm. [Worker source](https://github.com/ingonyama-zk/icicle-snark/blob/bf00385db19087a8a3f6d754b43b006254b1b465/src/main.rs) requires `exit` (EOF alone loops); [its timer](https://github.com/ingonyama-zk/icicle-snark/blob/bf00385db19087a8a3f6d754b43b006254b1b465/src/lib.rs) includes witness loading and JSON writes. Label that metric **cached file-inclusive**, not kernel-only. Verify each result with the shared snarkjs VK. CPU experiment: omit CUDA CMake step, build normally, choose `--device CPU`; Mac build still needs validation.

### Blackwell exclusions / sppark

[RTX 5090 is CC 12.0](https://developer.nvidia.com/cuda/gpus); [CUDA 12.8 introduces Blackwell support](https://developer.nvidia.com/blog/cuda-toolkit-12-8-delivers-nvidia-blackwell-support). Native `sm_80` cubins alone do not run on `sm_120`; compatible PTX can JIT, but its cold cost must be separated.

| Path | Concrete action / limitation |
|---|---|
| bellperson ec-gpu | [ec-gpu-gen 0.7.0 defaults](https://github.com/filecoin-project/ec-gpu/blob/ec-gpu-gen-v0.7.0/ec-gpu-gen/src/source.rs) list sm_75/80/86, not 120; do not assume a usable PTX fallback without inspecting the fatbin. Override `EC_GPU_CUDA_NVCC_ARGS='--optimize=3 --threads=1 --fatbin --generate-code=arch=compute_120,code=sm_120'` before `cargo build -q --message-format=short --release --features cuda`; verify BLS12-381 results, not BN254. OpenCL needs its ICD/development headers and offers no established 5090 result here. |
| sppark | Checkout v0.1.15 and submodules; [build code](https://github.com/supranational/sppark/blob/v0.1.15/rust/src/build.rs) probes nvcc and adds `compute_120,code=sm_120`. Run BN254 PoCs below. A ready sppark-based **BLS12-381** Groth16 prover exists as SupraSeal C2; no ready BN254 Groth16 entry point found in these pins. |
| cuZK / era / Zeknox | cuZK's `sm_35` build requires porting; do not run its old script unchanged. Era's architecture override is documented above, but it remains a primitive library. Zeknox's Groth16 fork and sm_120 support need separate integration work; neither substitutes for a ready selected prover. |

## Primitive benchmarks — built-ins and required adjustments

Use BN254 **G1** with full-width Fr scalars, and radix-2 **Fr** transforms; sizes `2^k`, `k=10…20`. Batch=1; report base/twiddle setup separately, host-transfer versus device-resident time separately. Correctness checks compare outputs against arkworks, never infer success from elapsed time. Commands run in the named pinned checkout; benchmark source edits are planned local benchmark patches, not changes made by this research lane.

| Library | Exact available command | Coverage / adjustment needed before comparable numbers |
|---|---|---|
| gnark-crypto v0.21.0 | `go test ./ecc/bn254 -run '^$' -bench '^BenchmarkMultiExpG1$/^[0-9]+_points$' -benchtime=3x -count=5`; `go test ./ecc/bn254/fr/fft -run '^$' -bench '^BenchmarkFFT$/bits$' -benchtime=3x -count=5` | [MSM](https://github.com/Consensys/gnark-crypto/blob/v0.21.0/ecc/bn254/multiexp_test.go) preallocates 2^24 points even when filtered: set `pow=20` and start its size loop at 10. [FFT](https://github.com/Consensys/gnark-crypto/blob/v0.21.0/ecc/bn254/fr/fft/fft_test.go) stops at 2^19: change loop to `i := 10; i <= 20; i++`. Same commands then cover target sizes; set `GOMAXPROCS=$THREADS`. |
| arkworks algebra v0.6.0 | `cargo bench -p ark-bn254 --features ark-ec/parallel --bench bn254 -- 'MSM-random for BN254::G1'`; `cargo bench -p ark-poly --features parallel --bench fft -- 'Subgroup FFT/'` | [MSM macro](https://github.com/arkworks-rs/algebra/blob/v0.6.0/bench-templates/src/macros/ec.rs) fixes `SAMPLES=1<<20`; parameterize that one value for k=10…20. [FFT bench](https://github.com/arkworks-rs/algebra/blob/v0.6.0/poly/benches/fft.rs) uses BLS12-381/MNT fields, **not BN254**: add an `ark-bn254` dev dependency and instantiate its existing generic radix-2 function for Fr over 10…20. No unmodified BN254 FFT command exists. |
| ICICLE / open-icicle v4.0.0 | In `wrappers/rust`: `BENCH_TARGET=CUDA MIN_LOG2=10 MAX_LOG2=20 cargo bench -p icicle-bn254 --bench msm -- ' x 1 with precomp = 1'`; `BENCH_TARGET=CUDA MAX_LOG2=20 cargo bench -p icicle-bn254 --bench ntt -- 'kNN kForward .* x 1$'` | Build open-icicle's local CUDA backend using the ICICLE-SNARK CMake pattern, isolated prefix. [MSM macro](https://github.com/ingonyama-zk/open-icicle/blob/v4.0.0/wrappers/rust/icicle-core/src/msm/mod.rs): set `cfg.is_async=false` or synchronize **inside** each timed iteration; stock synchronization is outside. Select precompute factor `[1]`, batch `[0]`, no zero bases, auto window `cfg.c=0`. [NTT macro](https://github.com/ingonyama-zk/open-icicle/blob/v4.0.0/wrappers/rust/icicle-core/src/ntt/mod.rs): replace `13u32..=max_log2` with `10u32..=max_log2`, `7u32..17u32` with `[0u32]`; otherwise the batch-1 filter matches nothing. CPU backend uses `BENCH_TARGET=CPU`. |
| sppark v0.1.15 | `BENCH_NPOW=10 cargo bench --manifest-path poc/msm-cuda/Cargo.toml --features bn254 --bench msm`; repeat with 11…20 | [MSM bench](https://github.com/supranational/sppark/blob/v0.1.15/poc/msm-cuda/benches/msm.rs) has the size environment variable. [NTT PoC](https://github.com/supranational/sppark/tree/v0.1.15/poc/ntt-cuda) has BN254 correctness tests, **no BN254 timing bench**; a small timer around `ntt_cuda::NTT` is required. Its Go NTT benchmark is Goldilocks, not a valid substitute. |
| bellperson / ec-gpu | In ec-gpu tag `ec-gpu-gen-v0.7.0`: `cargo bench --manifest-path gpu-tests/Cargo.toml --no-default-features --features cuda --bench multiexp` | bellperson v0.27.0 has no standalone BN254 MSM/NTT bench; `cargo bench` is not that measurement. [ec-gpu bench](https://github.com/filecoin-project/ec-gpu/blob/ec-gpu-gen-v0.7.0/gpu-tests/benches/multiexp.rs) is BLS12-381 and allocates 2^29 elements before filtering: lower max power to 20 and make its range inclusive. Appendix only; no BN254 NTT bench. |
| rapidsnark / snarkjs / bellman-ce | No maintained, size-configurable BN254 G1+Fr benchmark pair established in the inspected pins | Use their prover measurements; do not label witness/setup tests or PLONK/Goldilocks benches as Groth16 primitive numbers. Small wrappers are needed if their internal primitives become a separate target. |

The ICICLE commands time host-supplied scalars with cached device bases (MSM), and host input/output arrays (NTT); they are not device-resident kernel-only numbers. Preserve each benchmark patch and record exactly which transfers its timer includes. A filtered command that reports zero benchmarks is a failure, not a completed measurement.

## What we will report

`S = {2^10,2^14,2^18,2^20}` logical rows; `P = {2^10,…,2^20}` primitive lengths. No BLS12-381/Goldilocks result enters a BN254 speedup denominator.

| Prover / library | Platform | Sizes | Measurements |
|---|---|---|---|
| Bend / HVM2 | Mac CPU; Linux CPU; Linux CUDA if supported | S, P | Validated proof latency, MSM/NTT; setup/witness/compile separately; hardware/backend identified |
| gnark CPU; rapidsnark CPU | Mac arm64; Linux x86_64 | S | Single-core and all-core where controllable; warm prove-only and cold/file-inclusive kept separate; actual thread settings |
| snarkjs; ark-groth16 | Both CPUs | S | Reference latency; Node worker / Rayon settings; never advertised as production CPU SOTA |
| gnark + ICICLE | Linux + RTX 5090 | S | First proof versus warm proofs, GPU admission result, transfers/cache policy; same gnark rows and setup |
| ICICLE-SNARK | Linux + RTX 5090; optional Mac CPU | S | Cold and cached file-inclusive latency; identical Circom artifacts; experimental label |
| gnark-crypto; arkworks; ICICLE; sppark | CPU libraries on both hosts; CUDA libraries on Linux | P | G1 MSM and Fr NTT wall/device time, batch=1, preprocessing, transfer inclusion, exact benchmark patch |
| bellperson / SupraSeal / bellman-ce | Optional separate appendix | S | BLS12-381 Filecoin lineage / historical BN254 CPU; excluded from the selected production BN254 comparison |

For each admitted row publish commit/package locks, normalized matrix hash, wire/public counts, QAP domain, witness seed, PK size, CPU model/thread count, compiler flags, GPU/driver/CUDA, repetitions, median/p95, peak RSS/VRAM, verification result, and failures/timeouts. Run ten measured proofs after one warmup, process-isolated cold runs, one prover at a time. These are **SquareChain** results, not a universal production-circuit ranking.
