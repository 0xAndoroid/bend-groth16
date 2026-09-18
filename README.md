# bend-groth16

Benchmark subject: a Groth16 prover over BN254 written in [Bend](https://bend-lang.com) (HVM2), compared against arkworks, rapidsnark, snarkjs (CPU) and ICICLE/sppark + Bend-CUDA (GPU).

Layout:
- `docs/` — Bend idioms note, findings
- `ref/` — arkworks reference harness (Rust): circuits, pk/vk/witness export, verifier, CPU baselines
- `bend/` — the Bend implementation (field, curve, MSM, NTT, groth16)
- `comparators/` — rapidsnark / snarkjs / ICICLE setups + scripts
- `bench/` — raw benchmark results (JSON/CSV)
- `.journals/` — campaign journal
