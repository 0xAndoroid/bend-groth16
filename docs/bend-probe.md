# Bend 1 / HVM2 empirical probe (Mac mini M4, 10 cores, 16 GB)

Measured 2026-09-18. Sources: `bend/probe/*.bend`, `bend/probe/embed_gen.sh`. Companion docs-based note:
`docs/bend-idioms.md`.

## 1. Toolchain

| item | value |
|---|---|
| bend | `bend-lang 0.2.38` (`~/.cargo/bin/bend`) |
| hvm | `hvm 2.0.22` (`~/.cargo/bin/hvm`, "HVM2 32-bit Version") |
| install | `cargo install bend-lang hvm --locked` (crates.io; the GitHub repo `HigherOrderCO/Bend` is now Bend 2, a different language — Bend 1 lives at `HigherOrderCO/Bend1`, HVM2 at `HigherOrderCO/HVM2`; there are no GitHub releases) |
| C compiler | Apple clang 21.0.0 |
| `bend run-cu` | `CUDA runtime not available! If you've installed CUDA and nvcc after HVM, please reinstall HVM.` then `HVM output had no result` (no CUDA on the mini) |

**Run modes (important, non-obvious):** `bend run-c` is the C *interpreter* (`hvm run-c`), not a compiled
binary; `bend run-rs` is the single-threaded Rust interpreter; `bend run` == `run-c` in speed (both ~90 MIPS
on the tree probe). Real compiled speed needs `bend gen-c file.bend > x.c && clang -O2 -DTPC_L2=k x.c -o x -lm -lpthread`.

**Thread control:** the generated C has `#ifndef TPC_L2 / #define TPC_L2 3 // 10 cores` → threads = 2^TPC_L2,
defaulting to 8 (largest power of two ≤ core count). Override at compile time with `-DTPC_L2=0..3`;
there is no env var / runtime flag. The interpreter (`run-c`) is fixed at the default 8.

**Memory:** every HVM2 C process pre-allocates its heap: 6.4 GB RSS for the compiled `limbmul` runs on 16 GB
(3.1 GB in one run), 0.8–3.5 GB for the interpreter. Two concurrent compiled runs would swap on this box.

## 2. Numeric probe (`bend/probe/numeric.bend`, `bend run-c`)

Types: `u24` (default literal), `i24` (`+12`, `-3`), `f24` (`1.5`). No u32/u64: `return 4294967295` →
`Number literal outside of range for U24.`; `(u32 x)` → parse error `expected: ')'`. `run-c` and `run` agree.

| expression (u24) | result | note |
|---|---|---|
| `16777215 + 1` | 0 | wraps mod 2^24 |
| `0 - 1` | 16777215 | |
| `4095 * 4095` | 16769025 | |
| `4096 * 4096` | 0 | 2^24 wraps to 0 |
| `16777215 * 16777215` | 1 | (−1)^2 mod 2^24 |
| `4095*4095 + 4095 + 4095` | 16777215 | = 2^24−1 exactly: 12-bit mul + two 12-bit addends never wrap |
| `61680 & 65280`, `61680 \| 15`, `61680 ^ 65535` | 61440, 61695, 3855 | |
| `1 << 23`, `1 << 24` | 8388608, 0 | shift past width → 0 |
| `16777215 >> 12`, `/ 4096`, `% 4096` | 4095, 4095, 4095 | |
| `7 / 0` | 0 | no trap |
| `+8388607 + +1`, `-8388608 - +1` (i24) | −8388608, +8388607 | i24 wraps |
| `16777215 == -1` | 1 | bit-level equality across u24/i24 |
| `1.5 * 2.0`, `1.0 / 3.0` (f24) | 3.000, 0.333 | |

**Limb size:** products of two L-bit limbs must stay < 2^24 → L ≤ 12. With L = 12: `a*b + carry_in ≤
4095² + 4095 = 16773120`, and `a*b + c + d` with c,d < 2^12 is at most 2^24 − 1, so a mul-add with one carry
and one accumulator limb is exact, but a *column* of ≥2 products is not: carries must be propagated after every
limb product (row-by-row schoolbook, no lazy column accumulation). Carry-free accumulation needs L ≤ 8
(32·255² = 2 080 800 < 2^24 for 32 products). 254-bit BN254 element = 22 limbs × 12 bits (264 bits).

## 3. Parallelism probe (`bend/probe/parallel.bend`, 2^22 leaves)

Tree = `tsum(d)` splits in two per level (HVM parallelizes automatically); loop = tail-recursive `ssum`.
Both compute the same 2^22 leaf hashes. Quiet machine (load 2).

| program | threads | ITRS | HVM TIME | MIPS | wall |
|---|---|---|---|---|---|
| tree, compiled `-DTPC_L2=0` | 1 | 138 412 014 | 0.79 s | 175 | 1.06 s |
| tree, compiled `-DTPC_L2=1` | 2 | 138 412 014 | 0.39 s | 357 | 0.64 s |
| tree, compiled `-DTPC_L2=2` | 4 | 138 412 014 | 0.24 s | 575 | 0.39 s |
| tree, compiled `-DTPC_L2=3` | 8 | 138 412 014 | 0.15 s | 894 | 0.31 s |
| loop, compiled `-DTPC_L2=0` | 1 | 104 857 609 | 0.68 s | 153 | 1.00 s |
| tree, `bend run-c -s` (interp) | 8 | 138 412 014 | 1.60 s | 87 | 1.62 s |
| loop, `bend run-c -s` (interp) | 8 | 104 857 609 | 0.53 s | 198 | 0.56 s |
| tree, `bend run -s` (interp) | 8 | 138 412 014 | 1.47 s | 94 | 1.50 s |
| tree, `bend run-rs -s` | 1 | 138 412 014 | 2.07 s | 73 | 2.12 s |

Takeaways: compiled scales 5.1× on 8 threads (175 → 894 MIPS); compiled 1-thread already beats the 8-thread
interpreter ~2×; a sequential loop cannot use more than one core (the `-s` MIPS for the interpreted loop is
inflated by 8 spinning threads). ~33 interactions per leaf for the tree, 25 for the loop.

## 4. Input probe (`bend/probe/io.bend`, `bend/probe/embed_gen.sh`)

**File + stdin work under `run-c` and compiled.** `IO/FS/read_file(path)` returns `Result(List(u24), u24)`
of bytes; `IO/input()` reads a stdin line. `io.bend` decodes 3-byte LE limbs and returns `(count, checksum)`:

| input | mode | HVM TIME | wall | RSS |
|---|---|---|---|---|
| 2^14 limbs (48 KB) | `echo hello \| bend run-c io.bend -s` | 0.45 s | 0.47 s | 33 MB |
| 2^18 limbs (786 KB) | same | 0.76 s | 0.79 s | 420 MB |
| 2^18 limbs | `gen-c` + clang (3.1 s compile) | 0.69 s | 0.93 s | 404 MB |

Output was `(262144, 1123665)` in both modes; `hello` was echoed back. Byte lists cost ~133 interactions per
limb (34.9 M ITRS for 2^18 limbs) — fine for inputs up to ~10^7 bytes; no argv, path is a literal.
`IO/DyLib/open|call` (FFI to a .so/.dylib) exists as an alternative for binary loaders.

**Embedded literals** (`embed_gen.sh N` emits `def data(): return [N u24 literals]` + a list sum):

| N literals | .bend | `bend gen-c` | .c size | clang -O2 | `run-c` (interp) |
|---|---|---|---|---|---|
| 2^14 | 137 KB | 0.22 s, 73 MB | 8.4 MB | 55.5 s, 2.2 GB → runs 0.24 s | 0.20 s OK |
| 2^16 | 547 KB | 0.93 s, 279 MB | 33 MB | **251 s, 7.7 GB** → runs 0.91 s | 0.80 s OK |
| 2^18 | 2.2 MB | 3.8 s, 1.1 GB | ~130 MB | not attempted (>15 min extrapolated) | 3.8 s OK, 875 MB |
| 2^20 | 8.7 MB | 15.8 s, 4.8 GB | — | — | **fails**: `HVM output had no result`, 3.5 GB |

Ceilings: compiled path ≈ 2^16 literals (~4 min clang, 7.7 GB); interpreted ≈ 2^18 (2^20 dies). 5.8 M literals
(2^18 field elements × 22 limbs) is far beyond both → inputs must come through `IO/FS/read_file`.

## 5. Cost probe: 254-bit multiply (`bend/probe/limbmul.bend`, `limbmul_tree.bend`)

2^16 independent multiplies of pseudo-random operands, arranged as a binary tree (`many(16, seed)`), checksummed.
Both implementations verified limb-exact against Python on one product (`limbmul_one` / `lt_one`).

| representation | mode | ITRS | ITRS / mul | HVM TIME | MIPS | muls/s |
|---|---|---|---|---|---|---|
| A: List(u24), 22×12-bit, row schoolbook + carry | compiled, 1 thread | 3.33 G | 50 859 | 24.3 s | 137 | 2 690 |
| A | compiled, 8 threads (quiet box) | 3.33 G | 50 859 | **4.98 s** | 670 | **13 160** |
| A | compiled, 8 threads (box load 20–32) | 3.33 G | 50 859 | 13.3–14.8 s | 225–250 | ~4 600 |
| A | `run-c` interp, 8 threads | 3.33 G | 50 859 | 30.1 s | 111 | 2 180 |
| B: Tree of 32×8-bit limbs, carry-free 4-split | `run-c` interp, 8 threads | 16.26 G | 248 124 | 48.6 s | 335 | 1 350 |
| B | compiled, 1 / 8 threads | 3.4 G / 16.3 G | — | 209 s / 56.8 s | 16 / 286 | garbage result `x1fffffff` (heap exhausted at 6.4 GB RSS) |

Verdict: **A (List of 12-bit limbs) wins** — 4.9× fewer interactions per multiply and it runs to completion
compiled. B's carry-free tree is elegant and parallel inside a single multiply but the 4-split does 1024 leaf
products vs 484, allocates a fresh tree per level, and overflows the compiled heap. Even A costs ~51 k
interactions (≈105 per limb-product) per 254-bit multiply: at 670 MIPS that is ~13 k muls/s on all cores, i.e.
2^20 field muls ≈ 80 s, before any modular reduction. A Groth16 prover at 2^18–2^20 constraints (MSM + NTT
≈ 10^8 field muls) is ~2 h+ on CPU HVM2 — feasible as a benchmark subject, not competitive.

## 6. Recommendation

- **Limb size 12 bits, 22 limbs per BN254 element, little-endian `List(u24)`**; propagate carry after every
  limb product (`p = a*b + carry; p & 4095; p >> 12`), never accumulate columns. Montgomery reduction with a
  12-bit word is the natural fit (one `>> 12` per step).
- **Representation:** flat `List(u24)` (probe A). Avoid per-multiply tree structures (probe B); use trees only
  for the *outer* batch (`many`-style fork-join over independent elements) — that is where HVM's parallelism
  comes from (5.1× on 8 threads for tree reduce, 0× for loops).
- **Input path:** `IO/FS/read_file` on a binary of 3-byte LE limbs (working, ~1 s per 2^18 limbs); embedded
  literals cap at 2^16 (compiled) / 2^18 (interpreted). Path must be a string literal (no argv); run from the
  data directory or generate a tiny wrapper.
- **Thread control:** always `bend gen-c … | clang -O2 -DTPC_L2=3` (8 threads); `-DTPC_L2=0` for single-thread
  baselines. Do not benchmark with `bend run-c` (interpreter, 2–5× slower, fixed 8 threads).
- **Box hygiene:** one HVM2 compiled process at a time on the 16 GB mini (6.4 GB heap each); timings taken
  while other builds run (load > 20) are 2–3× off — record `uptime` with every number.

## Exact commands

```sh
export PATH=$HOME/.cargo/bin:$PATH
bend run-c bend/probe/numeric.bend
bend gen-c bend/probe/parallel.bend > p.c && clang -O2 -DTPC_L2=3 p.c -o p -lm -lpthread && ./p
perl -e 'srand(1); for(1..262144){ print substr(pack("V", int(rand(16777216))),0,3) }' > probe_limbs.bin
echo hello | bend run-c bend/probe/io.bend -s
bend/probe/embed_gen.sh 65536 > embed_16.bend && /usr/bin/time -l bend run-c embed_16.bend -s
bend gen-c bend/probe/limbmul.bend > lm.c && clang -O2 -DTPC_L2=3 lm.c -o lm -lm -lpthread && /usr/bin/time -l ./lm
```

## 7. Independent review — verdicts
- keep: numeric table (all rows reproduced; u32 rejected; 4 independent bigint pairs limb-exact, 44/44 limbs).
- keep: parallel scaling 174.8 → 896.2 MIPS (5.13×, load 2.6).
- **kill → runtime instability:** compiled probe A (2^16 254-bit muls) returned garbage `x1fffffff` in 1 of 3 identical runs (2/3: checksum 15636624, 3.99/4.12 s, 3.33 G ITRS ≈ 50 860/mul, 6.45 GB RSS). HVM2 2.0.22 compiled C output is not deterministic-safe on this box — a ceiling in itself.
- **kill → probe bug:** `io.bend` decodes bytes as signed char (`80 00 00` → 16777088 instead of 128); needs `& 255`. The 2^18-limb checksum with correct decoding is 14095185; timing (0.46 s) unaffected.
- keep: 2^20 embedded literals fail (`HVM output had no result`, 12.6 s, 3.44 GB RSS).
- corrections: MIPS spin-inflation remark is false (CLOCK_MONOTONIC); the 6.4 GB is calloc-reserved virtual (7 GiB) reported as RSS on macOS, not a fixed working set; `IO/FS/read_file` path can be an argument (not literal-only); operands in probe A reach 264 bits with only 4096 unique pairs (checksum still consumes every product).
