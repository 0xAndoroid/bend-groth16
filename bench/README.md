# bench/ — raw benchmark results

One JSON file per framework × host: `arkworks-<host>.json`, `bend-<host>.json`, … Files are
merged in place by the harness (`groth16-ref bench`), keyed by `log2`, so sizes can be run
separately (e.g. under `nohup`).

## `arkworks-<host>.json` schema (schema = 1)

Produced by `ref/` (`groth16-ref bench --log2 K` → `prove`; `groth16-ref bench --primitives` →
`msm_g1`, `msm_g2`, `ntt`, `fr_mul`). All times are wall-clock milliseconds, rayon using every
core (`threads`), release build. Each entry is the **median** of `iters` runs (default 3 below
2^16, 1 at/above); the raw samples are kept in `samples_ms`.

```jsonc
{
  "schema": 1,
  "framework": "arkworks",
  "versions": {"ark-groth16": "0.5.0", "ark-bn254": "0.5.0"},
  "host": "mac",                      // hostname -s, lowercased
  "cpu": "Apple M4",                  // sysctl -n machdep.cpu.brand_string
  "threads": 10,                      // rayon::current_num_threads()
  "git_head": "abc1234",
  "updated": "2026-09-18T05:40:00Z",  // RFC3339 UTC of the last merge
  "prove": {                          // full Groth16::prove (create_random_proof_with_reduction):
    "10": {                           //   constraint synthesis + R1CS→QAP witness map (NTTs) + MSMs
      "log2": 10, "num_constraints": 1024,
      "ms": 12.3, "iters": 3, "samples_ms": [12.5, 12.3, 12.1],
      "prove_matrices_ms": 11.0, "prove_matrices_samples_ms": [...],  // create_proof_with_reduction_and_matrices:
                                        //   matrices + z precomputed, fixed r,s (prover-only work, = what Bend does)
      "pk_source": "pk.bin",          // "pk.bin" (data/K/pk.bin reloaded) or "in-memory setup"
      "timestamp": "…"
    }
  },
  "msm_g1": { "10": {"log2": 10, "ms": 1.2, "iters": 3, "samples_ms": [...], "timestamp": "…"} },
  "msm_g2": { "10": {…} },            // 2^10..2^16
  "ntt":    { "10": {"log2": 10, "fft_ms": 0.1, "ifft_ms": 0.1, "iters": 3,
                     "fft_samples_ms": [...], "ifft_samples_ms": [...], "timestamp": "…"} },
  "fr_mul": {                         // single thread, 10^7 muls
    "dependent_muls_per_sec": 1.0e8,  // x = x * y chain (latency-bound)
    "independent_muls_per_sec": 1.5e8,// out[i] = a[i] * b[i] over a 2^20 batch (throughput-bound)
    "n_muls": 10000000, "batch": 1048576, "threads": 1, "timestamp": "…"
  }
}
```

Notes
- `prove` at `K` uses the frozen `SquareChain(2^K)` circuit and the deterministic witness
  (seed 42); the proof is verified once before timing (warm-up run, not counted).
- MSMs: `VariableBaseMSM::msm` over fresh random affine points and random scalars
  (no fixed-base tables). NTT: `Radix2EvaluationDomain::{fft,ifft}` over Fr.
- Sizes: MSM G1 and NTT 2^10..2^20, MSM G2 2^10..2^16 (override with `--max-log2`).
- Numbers taken while sibling lanes were compiling (load1 ≈ 6–16 on a 10-core M4) are upper
  bounds; rerun `groth16-ref bench --log2 K` on a quiet host before quoting them.
