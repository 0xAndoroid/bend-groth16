# comparators/gpu — RTX 5090 comparators

| path | what |
|---|---|
| `gnark-icicle/` | Go runner: gnark v0.16.3 `SquareChain(N)` (exactly N rows via one raw R1C), `groth16.Prove` on CPU or `icicleGroth.Prove` (icicle-gnark v3.2.2) with `-gpu` when built `-tags=icicle`; `-pin` = `WithPinKeysToGPU`. Verifies every proof with the native VK. |
| `icicle_snark_bench.py` | drives one ICICLE-SNARK (bf00385) worker: cold + warm `prove` per K on the shared Circom zkey/wtns; snarkjs verify |
| `icicle-prim/` | ICICLE v4.0.0 BN254 G1 MSM / Fr NTT timer, device-resident and host-input variants, synchronous calls |
| `sppark/ntt_timer.rs` | sppark v0.1.15 BN254 NTT timer example (the PoC has no BN254 timing bench) |
| `primitives.py` | runs icicle-prim + sppark msm bench + ntt_timer → `bench/box-gpu-primitives.json` |
| `run-gpu.sh` | the whole GPU sweep |

Build/run details: `../box/README.md`, results: `../../docs/box.md`.
