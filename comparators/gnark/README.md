# gnark comparator — Groth16 / BN254, SquareChain(N)

Go CLI timing [gnark](https://github.com/Consensys/gnark) `groth16.Prove` on the canonical
`SquareChain(N)` circuit (private `x0 = 3`, `x[i+1] = x[i]^2`, public `y = x[N]`; exactly `N`
constraints, `N+2` wires, one public scalar) and gnark-crypto BN254 primitives. Recipe:
`docs/comparators.md` §"gnark frontend and timer" and §"Primitive benchmarks".

Pins: gnark **v0.16.3**, gnark-crypto **v0.21.0**, Go 1.27.1 (`brew install go`). CPU only (no
`icicle` build tag).

## Commands

```sh
cd comparators/gnark && go build -o gnark-bench .
./gnark-bench prove --log2 14                       # GOMAXPROCS default (all cores)
./gnark-bench prove --log2 14 --gomaxprocs 1        # single core
./gnark-bench prove --log2 20 --iters 1 --out ../../bench/gnark-macmini.json
./gnark-bench primitives [--max-log2 20] --out ../../bench/gnark-macmini.json
```

`prove`: compile (asserts `GetNbConstraints() == N`, abort otherwise) → `groth16.Setup` → one
warm-up proof → `iters` timed `groth16.Prove` (default 5 for K≤14, 3 for K≤18, 1 above), every
proof verified with `groth16.Verify`. `ms` is the median of full `Prove` (which includes gnark's
witness solver); `solve_ms` is a *separate* timing of `ccs.Solve` alone, not subtracted.
`--out` merges results into the JSON (per `bench/README.md`; 1-thread runs land under `prove_1t`).

`primitives`: G1 `MultiExp` 2^10..2^20 and G2 `MultiExp` 2^10..2^16 over distinct points
(`p_i = 2p_{i-1} + g`) and random full-width Fr scalars, `NbTasks = GOMAXPROCS` (`msm_*`) and
`NbTasks = 1` (`msm_*_1t`); `fft.Domain` `FFT(DIF)` / `FFTInverse(DIT)`, coset off, 2^10..2^20
(`ntt`, `ntt_1t`); Fr `Mul` throughput on one goroutine, 10^7 dependent muls (`x = x*y`) and
10^7 independent muls over a 2^20 batch. 5 iters ≤2^16, 3 above; median reported. Domain
construction and point/scalar generation are outside the timers.

Note: gnark's prover sizes its MSM goroutines from `runtime.NumCPU()`, so `GOMAXPROCS=1`
serialises them onto one OS thread rather than changing the algorithmic split.

## Results — Mac mini, Apple M4 (10 cores), 2026-09-18

Raw data: `bench/gnark-macmini.json`. **Host was shared with sibling lanes compiling
(load1 ≈ 8–21 on 10 cores); all numbers are upper bounds, 1-thread K=14 especially noisy.**
QAP domain = N (gnark uses `next_pow2(N)`); `num_public = 2` counts the constant-one wire.

### Prove (ms, median; proofs verified)

| K | N | 10 thread | 10 thread samples | solve | 1 thread | 1 thread samples | setup (10 thread) |
|---|---|---|---|---|---|---|---|
| 10 | 1024 | 13.43 | 13.32, 13.75, 13.81, 12.68, 13.43 | 0.04 | 56.33 | 60.43, 48.57, 54.19, 56.33, 63.1 | 80.85 |
| 14 | 16384 | 97.32 | 96.21, 97.49, 97.32, 98.34, 96.06 | 0.57 | 1845.38 | 1275.13, 1845.38, 1314.42, 3284.53, 3239.74 | 912.72 |
| 18 | 262144 | 928.47 | 928.47, 991.28, 912.93 | 8.15 | 7008.1 | 7008.1, 8782.66, 6663.41 | 13246.65 |
| 20 | 1048576 | 3928.79 | 3928.79 | 37.57 | — | skipped (1-thread setup alone ≈ 5 min) | 71209.79 |

### Primitives (ms, median)

| log2 | G1 MSM 10 thread | G1 MSM 1 thread | G2 MSM 10 thread | G2 MSM 1 thread | FFT 10 thread | iFFT 10 thread | FFT 1 thread | iFFT 1 thread |
|---|---|---|---|---|---|---|---|---|
| 10 | 2.1 | 6.35 | 6.82 | 34.84 | 0.08 | 0.12 | 0.16 | 0.16 |
| 11 | 3.82 | 11.37 | 20.36 | 64.51 | 0.12 | 0.13 | 0.36 | 0.41 |
| 12 | 6.76 | 20.54 | 30.55 | 127.87 | 0.23 | 0.27 | 0.24 | 0.28 |
| 13 | 10.25 | 34.91 | 41.68 | 151.7 | 0.43 | 0.73 | 1.71 | 0.64 |
| 14 | 16.26 | 58.97 | 70.98 | 295.69 | 0.64 | 0.91 | 1.17 | 1.29 |
| 15 | 28.21 | 109.22 | 121.11 | 536.22 | 1.52 | 1.35 | 2.52 | 3.74 |
| 16 | 43.39 | 196.68 | 241.75 | 920.64 | 3.49 | 3.34 | 5.61 | 6.1 |
| 17 | 82.89 | 480.06 | — | — | 7.17 | 8.13 | 12.7 | 13.8 |
| 18 | 152.89 | 673.91 | — | — | 14.45 | 13.37 | 33.08 | 35.62 |
| 19 | 281.49 | 1982.06 | — | — | 24.66 | 26.49 | 97.08 | 83.85 |
| 20 | 848.4 | 3877.01 | — | — | 42.66 | 41.3 | 122.69 | 128.33 |

Fr `Mul`, single thread: 6.7e7 dependent muls/s, 1.08e8 independent muls/s.
