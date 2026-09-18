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

Raw data: `bench/gnark-macmini.json` (every entry carries the host `loadavg` at sample time).
**Host was shared with sibling lanes compiling (load1 ≈ 9–20 on 10 cores); all numbers are
upper bounds** — 10-thread proves suffer most (K=14 measured 97 ms on a quieter moment vs 194 ms
below), rerun on a quiet host before quoting. QAP domain = N (gnark uses `next_pow2(N)`);
`num_public = 2` counts the constant-one wire.

### Prove (ms, median; proofs verified)

| K | N | 10 thread | 10 thread samples | solve | 1 thread | 1 thread samples | setup (10 thread) | load1 (10t / 1t) |
|---|---|---|---|---|---|---|---|---|
| 10 | 1024 | 14.39 | 10.74, 20.4, 21.56, 14.39, 12.02 | 0.04 | 45.82 | 45.82, 45.46, 45.82, 45.85, 45.5 | 104.09 | 16.2 / 20.1 |
| 14 | 16384 | 194.1 | 161.72, 194.1, 220.21, 180.89, 197.51 | 0.54 | 431.07 | 434.29, 433.21, 430.15, 431.07, 428.36 | 2037.98 | 16.2 / 18.8 |
| 18 | 262144 | 1249.77 | 1226.43, 1249.77, 1358.32 | 8.25 | 4661.6 | 4612.03, 4661.6, 4668.85 | 23317.98 | 18.7 / 11.0 |
| 20 | 1048576 | 3330.94 | 3330.94 | 86.29 | — | skipped (1-thread setup alone ≈ 8 min) | 76968.4 | 20.1 / — |

1-thread variance (review finding): a first run recorded K=14 samples of 1275–3284 ms (2.5×
spread). Cause is host contention, not GC: `GODEBUG=gctrace=1` shows 14 GCs in the whole run and
`GOGC=off` reproduces the same spread (554–932 ms); a single-`P` Go process gets a fluctuating
share of a saturated host. Re-measured at load1 ≈ 19 the same run gives 428–434 ms (1 % spread),
so no code stabilisation is applied — read `loadavg` next to each entry instead.

### Primitives (ms, median; per call)

| log2 | G1 MSM 10 thread | G1 MSM 1 thread | G2 MSM 10 thread | G2 MSM 1 thread | FFT 10 thread | iFFT 10 thread | FFT 1 thread | iFFT 1 thread |
|---|---|---|---|---|---|---|---|---|
| 10 | 1.14 | 6.01 | 4.9 | 21.97 | 0.04 | 0.05 | 0.05 | 0.06 |
| 11 | 1.99 | 10.75 | 8.47 | 38.1 | 0.05 | 0.07 | 0.11 | 0.13 |
| 12 | 3.72 | 19.7 | 13.9 | 71.28 | 0.12 | 0.12 | 0.24 | 0.28 |
| 13 | 5.6 | 33.8 | 19.16 | 95.44 | 0.2 | 0.23 | 0.54 | 0.6 |
| 14 | 9.98 | 57.99 | 30.47 | 166.63 | 0.34 | 0.41 | 1.16 | 1.29 |
| 15 | 20.26 | 104 | 58.19 | 309.31 | 0.66 | 0.75 | 2.55 | 2.82 |
| 16 | 33.85 | 183.98 | 103.19 | 569.25 | 1.29 | 1.48 | 5.43 | 5.91 |
| 17 | 62.48 | 348.53 | — | — | 3.25 | 3.68 | 11.7 | 12.65 |
| 18 | 124.25 | 630.52 | — | — | 5.13 | 7.19 | 24.89 | 26.88 |
| 19 | 268.79 | 1172.63 | — | — | 12.58 | 13.24 | 51.9 | 56.33 |
| 20 | 399.9 | 2350.82 | — | — | 29.27 | 29.85 | 110.93 | 119.05 |

Primitives ran at load1 ≈ 7–11. Fr `Mul`, single thread: 7.2e7 dependent muls/s, 1.17e8
independent muls/s.

## Tests

`go test ./...` — `TestSquareChain`: `GetNbConstraints() == N`, the correct `y` solves, `y+1` is
rejected by the solver (the raw output row really constrains the public output).
