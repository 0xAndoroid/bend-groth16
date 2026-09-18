# bend2 — Groth16 prover in Bend 2 (BN254)

Bend **2.0.5** (`~/.bend/bin/bend`, always with `BEND_NO_TELEMETRY=1`; plain `bend` on the mini is Bend 1).
Facts and measured limits: `docs/bend2-idioms.md`. Binary interchange format: `FORMAT.md`.

Prove: `sh bend2/scripts/prove.sh K [--threads 1]` builds `prove.bend`, proves `data/K/bend`, verifies with the
arkworks harness and compares to `proof_ref` (prints the `T <phase> <ms>` lines, then `OK`/`INVALID` and
`EQUAL`/`DIFFERENT`). `BENDG_GPU=1` dispatches the five MSMs and the QAP NTTs through `!` (Metal / CUDA); the
prover itself reads `BENDG_DATA` and prints `A`/`B`/`C` then `T load evals qap msm_a msm_b1 msm_b2 msm_h msm_l total`.
`scripts/bench_prover.sh run cpu1|cpu_all|gpu RUNS K` repeats it and emits the `bench/bend2-*.json` rows.

## Layout

| Path | What |
|---|---|
| `src/fr.bend`, `src/fq.bend` | BN254 Fr / Fq: 16 × 16-bit limbs in `U32`, Montgomery R = 2^256 (**generated** by `gen/gen_field.py`) |
| `src/fq2.bend` | Fq2 = Fq[u]/(u²+1), Karatsuba mul, 32 words at rest |
| `src/g1.bend`, `src/g2.bend` | Jacobian curve arithmetic over Fq / Fq2 (**generated** by `gen/gen_curve.py` from one template) |
| `src/bin_io.bend` | `load_u32(path, d, pad)`: little-endian `.bin` → `Array<U32>` of 2^d slots, file word w at index `pad + w` |
| `src/msm.bend`, `src/ntt.bend` | Pippenger MSM (G1/G2, fork tree of private bucket arrays, `g1_with/g2_with(points, scalars, n, c, fd)`), Stockham NTT / iNTT / coset FFT + QAP `h` (**generated** by `gen/gen_msm.py`, `gen/gen_ntt.py`) |
| `src/groth16.bend` | header/CSR loading, evaluation vectors, MSM accumulators, final combination |
| `prove.bend` | entry point: phases, `T` timing lines, `BENDG_GPU` dispatch |
| `tests/` | `test_{fr,fq,g1,g2,ntt,msm}.bend`, `probe_show.bend`, `test_prove.sh` (K=4 end to end), `run.sh` (all of them) |
| `bench/` | `field_mul.bend`, `g1_add.bend`, `msm.bend`, `ntt.bend` + `msm_results.md`, `ntt_results.md`, `prover_results.md`, `box_results.md` |
| `scripts/` | `prove.sh`, `bench_prover.sh` |
| `tools/` | `export_bin.py` (JSON → `.bin`), `verify_bin.py`, `proof_to_json.py` (see `tools/README.md`) |
| `gen/` | `gen_field.py`, `gen_curve.py`, `gen_msm.py`, `gen_ntt.py`, `ref_qap.py` (QAP reference vectors) |

Regenerate: `uv run python bend2/gen/gen_field.py && uv run python bend2/gen/gen_curve.py` (msm/ntt: `gen_msm.py`, `gen_ntt.py`).

## Module idiom (verified by compiling)

```python
import Base
import ./fq.bend as Q          # relative to the importing file; ../src/fq.bend from tests/
import ./fr.bend as R

def f(x: Q.Fq, k: R.Fr) -> Q.Fq:   # type: <alias>.<TypeName>
  match x:
    case Q.Fq{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13, l14, l15}:   # constructor patterns are qualified too
      Q.Fq.mul(Q.Fq{l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13, l14, l15}, Q.Fq.r2())
```

- The alias prefixes the module's **full** def name: `fq.bend` defines `Fq.mul` → callers write `Q.Fq.mul`; `bin_io.bend` defines `load_u32` → `Io.load_u32`. Types flow transitively: `g1.bend`'s `G1{x: Q.Fq, …}` unifies with a test's own `Q.Fq` when both import the same file.
- Zero-arg constants are defs: `Q.Fq.one()`, `G.G1.infinity()`.
- Array reads return `Array<U32> & T` and **a pair can only be opened in a def that receives it as a parameter** (`(a, +x) = p`); `(a, x) = a[i]` inline is rejected. Hence the `*.from_array.sN` stage defs and the test stage chains. Pair fields used twice need `+`.
- Record fields declared `+` come out reusable in patterns; loop counters that are used twice need `case 1n++p`.

## Frozen API

**Fr / Fq** (`F` = `Fr` or `Fq`): `F.zero() F.one() F.r2() F.raw_one() F.modulus()`, `F.add F.sub F.neg F.mul F.sqr F.inv`, `F.is_zero -> U32`, `F.eq -> U32`, `F.from_canonical` (raw record → Montgomery), `F.to_canonical`, `F.from_array(a, i: Nat) -> Array<U32> & F` (16 words at 16·i), `F.to_array(a, i, x) -> Array<U32>`, `F.show` (canonical 0x + 64 hex digits), `F.show_raw`, `F.lo`; Fr only: `Fr.limb(j, x)`, `Fr.bits_window(x_canonical, lo: Nat, width ≤ 16) -> U32`.

**Fq2**: `zero one add sub neg mul sqr inv is_zero eq show`, `from_array(a, i)` (32 words at 32·i), `from_array_at(a, u)` (c0 = Fq element u), `to_array`.

**G1 / G2** (`G`): `G.infinity() GAff.infinity()`, `G.from_affine G.to_affine` (one inversion), `G.double G.add G.add_mixed G.neg GAff.neg`, `G.mul_scalar(p, k: Fr canonical)`, `G.eq_affine -> U32`, `G.is_inf GAff.is_inf -> U32`, `GAff.from_array(a, i)` (G1: 32 words at 32·i; G2: 64 at 64·i), `GAff.from_array_at(a, u)` (x starts at 16-word unit u), `GAff.to_array`, `G.show_affine` (`x y`, G2: `x0 x1 y0 y1`).

Infinity: affine = both coordinates zero (FORMAT.md), Jacobian = z zero. `add`/`add_mixed` compute the generic formula, then a Bool match picks the special case (P = ∞, Q = ∞, P = ±Q).

## Tests

`sh bend2/tests/run.sh` builds and runs every test against `data/vectors/bend/*.bin` (produced by
`tools/export_bin.py --vectors data/vectors` from `groth16-ref vectors`) and `data/{4,10}/bend`, then `test_prove.sh`.
Exit 1 unless every test prints only `PASS` lines and the K=4 prove is `OK` + `EQUAL`.

| Test | Checks |
|---|---|
| `test_fr`, `test_fq` (`PASS 64`) | add sub mul neg inv sqr from/to_canonical against arkworks vectors |
| `test_g1` (`PASS 32`), `test_g2` (`PASS 16`) | add, add_mixed, double, neg, mul_scalar, affine neg, add reversed, affine round trip; cases 0–2 are ∞, P = Q, P = −Q |
| `test_ntt` (`PASS 8`; `K=4`, `K=10`) | NTT/iNTT on `ntt_small_*.bin`; QAP `h` against `gen/ref_qap.py` references |
| `test_msm` | `msm_small_{8,64,1024}.bin` |
| `probe_show` | hex printing and `Fr.bits_window` values (printed, eyeballed) |
| `test_prove.sh` | `prove.sh 4` → `OK` + `EQUAL` (`PASS prove K=4`) |

## Bench (M4 Mac mini, 10 cores, Metal; medians of 3; checksums equal across configs)

| Bench | `--threads 1` | 10 threads | Metal |
|---|---|---|---|
| `field_mul` 2^20 Fr.mul, FD 14 | 114 ms (9.2 M/s) | 22 ms (48 M/s) | 46 ms (FD 14; overhead-bound) |
| `field_mul` 2^24 Fr.mul, FD 14 / 16 | 1829 ms (9.2 M/s) | 352 ms (48 M/s) | **73 ms** (FD 16, **230 M/s**) |
| `g1_add` 2^20 G1.add_mixed, FD 14 | 1570 ms (0.67 M/s) | 301 ms (3.5 M/s) | **99 ms** (10.6 M/s) |

`MODE=cpu|gpu N=<log2 ops> FD=<fork depth> ./field_mul [--threads N]`; same for `g1_add`. A `!` call costs ~50 ms fixed, so Metal only wins from ~2^22 ops up.
