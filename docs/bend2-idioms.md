# Bend 2 idioms for the BN254 Groth16 benchmark

**Checked 2026-09-18 on the Mac mini (Apple M4, 10 cores, 16 GB, Metal).** Target: **Bend 2.0.5**
(`bendlang/bend` @ [`0b7e2b1`](https://github.com/bendlang/bend/commit/0b7e2b11c1054f5d0f4eb955cadb47997ef1115d),
version commit 38ad338 2026-09-17). Bend 2 is the primary target; Bend 1 / HVM2 is covered by
`docs/bend-idioms.md` and shares nothing with this note (Bend 1 programs and HVM do not carry over). All file:line cites are into `bendlang/bend` at `0b7e2b1`. Probes:
`bend2/probe/*.bend`, raw outputs `bend2/probe/*.out.txt`.

## 1. What Bend 2 is

| Aspect | Fact (cite) |
|---|---|
| Language | Python-shaped syntax, Lean-like dependent types, **affine** values (each variable used ≤1× unless `+`), mandatory termination, no mutual recursion, no `if`, no computed `match`. `guide/GUIDE.md:87-126` |
| Runtime model | **Not interaction nets / not HVM.** One C file is both CPU program and GPU kernel: "each def compiles to a segment of a flat state machine, a call is a jump, and a parallel call creates a join task plus one task per call" (`GUIDE.md:270-282`). Terms are 64-bit words in one shared arena; no GC — `match` frees the node it opens, only `+` values are refcounted (`comp.ts:3342`, `3741-3752`). |
| Scheduler | Contention-free binary fork-join over a 128×128 grid of task rings; **a task is placed once and never migrates — no work stealing** (`comp.ts:2474-2560`, `4212-4236`, `docs/BendRT/main.typ:114`). Hence "balanced calls" is a hard performance requirement. |
| Compiler | TypeScript (`bend2/bend.ts` checker, `bend2/comp.ts` C/JS emitter + runtimes, 6.2k lines) run by **Bun**. Target chosen by output extension only (`main.ts:196-211`): `-o x.c` emits C, `-o x.js` JS, `-o x` builds a binary. |
| C build | `clang -std=c11 -O3 file.c -lpthread -lm -o bin` (macOS adds `-x objective-c -fobjc-arc -fmodules`); compiler = `$CC`, else `clang`, else newest `clang-NN` ≥14 (≥19 / Apple ≥17 when `!` is used, for `#embed`) (`main.ts:217-276`). No `-march`, no LTO. |
| GPU build | **Never nvcc / never `xcrun metal`.** The binary `#embed`s its own C source (`comp.ts:3457-3464`) and compiles it at first run: Metal via `newLibraryWithSource:` (`comp.ts:4789-4799`), CUDA via **NVRTC** with `--gpu-architecture=sm_<major><minor>` queried from the device (`comp.ts:4934-4951`). `bend f.bend -o f` then runs `./f --gpu-build` to cache the pipeline as `f.gpu` (`main.ts:269-270`); the `.gpu` file must stay beside the binary. |
| Run mode | `bend f.bend` type-checks then: `main : IO(_)` → generated JS evaluated in Bun (`comp.ts:1271-1275`); pure `main` → normalized by the checker's interpreter ("slow for big work", `GUIDE.md:192`). **Run mode never touches clang; benchmarks must use `-o bin`.** |

### Install (as done here)

```sh
curl -fsSL https://bend-lang.com/install.sh -o install.sh
PATH="$HOME/.bend/bin:$PATH" BEND_NO_TELEMETRY=1 sh install.sh   # PATH pre-set ⇒ installer does NOT edit ~/.zshrc
~/.bend/bin/bend --version                                          # Bend 2.0.5
```

- Layout: `~/.bend/bin/bend` is a 3.5 KB **sh launcher** that runs `bun ~/.bend/current/bend2/main.ts`; `current -> app/2.0.5/wYTOWc` (704 KB: `bend2/{main,bend,comp}.ts`, `base.bend`, `effs/*.{c,js}`, `guide/GUIDE.md`). Installs Bun if missing.
- The launcher **auto-updates and pings** `bend-lang.com` on every run unless `BEND_NO_TELEMETRY=1` (`install.sh` launcher comment). Always export it.
- **PATH collision:** a Bend 1 install may exist as `~/.cargo/bin/bend`. The installer prepends `~/.bend/bin` to the rc file only when it is not already on `PATH`; with the trick above nothing is written (verified: `grep .bend ~/.zshrc` empty). **Invoke Bend 2 by absolute path `~/.bend/bin/bend`** in scripts; `which bend` on this machine is Bend 1.
- Needs clang: Apple clang 21 (`/usr/bin/clang`) works incl. Metal; Homebrew clang fails with `-fmodules` (issue #769). No CUDA on the mini.
- Compile times: hello 0.66 s; `montmul.bend` (1.8k lines, with Metal pipeline build) 6 s.

## 2. Types and numerics (measured: `bend2/probe/numeric.out.txt`)

Native numbers: **`U32`, `F32`, `Nat` only** — no U64/I64/F64, no signed ints (README §Limitations; `comp.ts:136` `WORDS = {U32: W32, F32: W32, Nat: W64}`).

| Type | Runtime | Ops (all `T.verb` defs; sugar inside `( … : T)`) | Measured |
|---|---|---|---|
| `U32` | 32-bit in a 64-bit word; C op `(u64)((u32)a op (u32)b)` (`comp.ts:415`) | `add sub mul div mod` (`+ - * / %`), `and or xor not` (`.&. .|. .^.`), `shl/shr` by 1, `shln/shrn` by a `Nat` (`<< >>`), `is_eq … is_ge` (`< <= > >=`), `cmp`, `to_nat/from_nat`, `show/read`, `pow`, `min/max` (`base.bend:1257-1443`) | `4294967295+1 = 0`, `0-1 = 4294967295`, `65535*65535 = 4294836225`, `65536*65536 = 0`, `65536*65537 = 65536`: **wrapping, no widening, no mul-hi** (grep `mulhi|__umulhi|u64_` in `comp.ts`/`base.bend`: nothing). `1<<31 = 2147483648`, `1<<32 = 0`, `1<<33 = 0`, `x>>32 = 0`: **shift count ≥32 yields 0** (not masked; `comp.ts:193-194`). `7/0 = 0`, `7%0 = 7` (defined, no trap). `from_nat(2^32+5) = 5` (truncates). |
| `Nat` | **A 48-bit machine word**, not a bignum, not unary: `NAT_IMM = 2^48-1` (`comp.ts:3375-3376`); `add sub(saturating) mul divmod cmp` are O(1) intrinsics (`comp.ts:252-287`) | `+ - * / %` without `: T`, `Nat.pow`, `Nat.divmod`, `show/read`, patterns `0n` / `1n+p` / `1n++p` (p reusable). **No bit ops.** | `2^32*2^15 = 140737488355328`, `2^48-1 = 281474976710655`, `(2^24-1)^2 + 2(2^24-1) = 281474976710655` fits exactly; `2^47*2` → **abort** `bend: a Nat past the largest immediate 2^48-1`; `5-7 = 0`. |
| `F32` | IEEE single, `fp contract(off)`, NVRTC `--fmad=false` (`comp.ts:3152`) | full libm set | `1.0/3.0 = 0.33333334`; axiomatic, useless for us. |

**Nat literal ceiling (compiler bug):** the checker expands `Nn` to unary `Succ` — `5000n` compiles, **`10000n` dies with "the machine stack overflowed"**, `4294967301n` hangs >20 s (issues #779, #791). Build large constants with `Nat.pow(2n, k)` at runtime. U32 literals up to `4294967295` are fine.

Operator sugar nests with normal precedence: `((a * b : U32) + c : U32)` and `(a * b + c : U32)` both compile and agree with Python on wrapping inputs (`$TMPDIR` probe `syn.bend`).

### Limb scheme for 254-bit Montgomery arithmetic

No 32×32→64 product and no carry flag exist, so 32-bit limbs are out. Choices:

| Scheme | Cell bound | Verdict |
|---|---|---|
| **16 × 16-bit limbs in `U32`** (chosen) | `t + a·b + c ≤ (2^16-1)^2 + 2(2^16-1) = 2^32-1` — one CIOS cell is exact in U32 | 16 outer rounds × (16 + 16) cells; only `mul add and shrn`. **Validated 1000/1000** vs bigint (`bend2/probe/check_montmul.py`). R = 2^256. |
| 11 × 24-bit limbs in `Nat` | `(2^24-1)^2 + 2(2^24-1) = 2^48-1` fits the 48-bit Nat exactly | Fewer cells (11×22) but Nat has no `and/shr`: split via `Nat.divmod(x, 2^24)` (a hardware div per cell) and any overflow aborts the process. Untested; try only if the 16-bit version is the bottleneck. |
| 12-bit limbs | needless | U32 already holds a 16-bit product. |

## 3. Data structures and getting data in

- **`Array<T>`** (`base.bend:67-69`, a `Type`, so single-owner): runtime is one **flat block** — packed 32-bit cells when every element word is 32-bit (`TAG_BUF`), else one 64-bit term per word (`comp.ts:1008-1011`, `4006-4051`). `Array.new(U32, d, v)` / `[v : U32*n]` / `[v : U32^d]` allocate **2^d slots** (power of two only). `a[i]` reads → `(Array<U32> & U32)`; `a[i] <- v` writes in place and re-binds `a`; `Array.get/set/swap/size/clone/map/to_list`. **Index wraps** (`i & (n-1)`). Max `d + lgs ≤ 31`: 2^31 U32s (measured: 2^31 OK, 2^32 → `an array past the deepest block class 31`). `get/set` are O(1) loads/stores; **matching `ANode{xs, ys}` copies both halves** (issue #804) — never destructure an array, index it.
- **`List<T>`** cons cells (~40 B/cell measured: 2^26 cells = 2.7 GB RSS); `String` = list of `Char`. Records: `type St is Type: St{a: Array<U32>, +n: U32}` (fields marked `+` come out reusable); tuples `A & B`.
- **Opening a pair/record is a `match` and a match may only inspect a parameter or pattern-bound variable** (`GUIDE.md:123-126`). `(a, v) = a[i]` inline is rejected ("a match cannot scrutinize a computed value: give it its own def"). Idiom (from `bench/runtime/bfs/main.bend`): the loop def takes the *pair* as a parameter, opens it at the top of the case, and passes the *next* read to the recursive call: `total(p, i+1, total.step(acc, a[i]))`. Defs must be declared **before** first use.
- **Input:** no argv (`./bin foo` → `bend: unknown option foo`, `comp.ts:5891`), no stdin effect; `IO.get_env` (strings, `U32.read` to parse), `File.open(path, "r")` + `File.read_bytes(f, max)` → `List<&2, U32>` of bytes (one cell per byte, a single `read()` per call so loop until empty; `effs/file_read_bytes.c`), `File.read` → `String`. `/dev/stdin` opens as a file (measured). **Practical PK feed:** little-endian `.bin` of U32 limbs, read in 64 KB–1 MB chunks and packed into `Array<U32>`: **2^21 words (8 MB) in 25–35 ms**, checksum verified (`bend2/probe/io.bend`). A G1 affine point is 32 U32 limbs (16 per coordinate, `bend2/FORMAT.md`): 2^18 points = 2^23 words = 32 MiB ⇒ ~4× that cost. Alternatively generate witnesses in-program from a seed for benchmarks.

## 4. Parallelism

- **Primitive:** the parallel let `a b = f(x) g(y)` (n-ary: `a b c d = …`) = one join task + one task per call (`comp.ts:2474-2560`). Promise: calls independent (guaranteed by purity/affinity) **and of equal duration** (yours; `GUIDE.md:147-157`). Recursion over a `Nat` depth (`case 1n++p: a b = go(p,…) go(p,…)`) is the canonical balanced tree. There is **no parallel `map`/`fold`/`for`** in Base other than `Array.map` (which forks per node, `base.bend:2243-2249`); write the tree yourself.
- **`f!(args)`** (`bend.ts:2016-2023`: only a *named top-level def* immediately applied) hands that call and every parallel let inside it to the GPU; without a GPU (or `--gpu off`) it runs on all CPU cores. Plain calls also run in parallel on the CPU (issue #767 fixed; measured 5.4–6× on 10 cores).
- **CPU threads:** `./bin --threads N` (1..128, default = online CPUs; `comp.ts:3479-3485`, `4703-4716`). No env knob, no `bend`-CLI flag.
- **GPU geometry:** 128 threads × 2^CUBE_LOG groups; Metal default 128 groups = **16384 lanes** (`comp.ts:3397-3448`); CUDA sizes groups from L2 (16..128). Three passes per round (grow/work/pack) driven by the host (`comp.ts:4770-4779`). Per-lane value stack 2^11 words → `ERR_DEEP` if a leaf recurses too deep non-tail. Fixed dispatch cost measured **~55 ms per `!` call** (plus ~350–500 ms the first call of a process to load the pipeline): a `!` must carry ≥10^7 U32-ops to pay off.
- **Restrictions under `!`:** no compile-time check; a device task reaching a host-only def (any IO effect, `F32.show/read`) traps `a function the device does not hold` (`comp.ts:4366-4371`, `4582`). Closures and arrays are allowed on device; Metal maps the same arena zero-copy (`newBufferWithBytesNoCopy`, `comp.ts:4835-4839`); CUDA uses managed memory and **requires** `CONCURRENT_MANAGED_ACCESS` (`comp.ts:4894-4912`). Metal span defaults to 2 GB (`--gpu 8GB` raises; `comp.ts:4828-4833`).

**Reviewer checklist — "Bend 2 used properly":**
1. Benchmarks run a `-o` binary, never `bend f.bend` (JS/interpreter).
2. Every hot loop is a balanced `Nat`-depth fork tree; leaves do ≥ a few µs of sequential work (fork depth ≈ log2(cores)+4 on CPU; ≥14 on Metal).
3. The GPU entry is one `f!(…)` per phase, not per element; `!` reachable code has no IO.
4. Field elements are records of `+U32` limbs or `Array<U32>`; no `Nat` in arithmetic hot paths (48-bit abort), no Nat literals ≥ 5000.
5. Arrays are indexed, never `match`ed; reads flow through stage defs; no `Array.clone` in loops.
6. Thread scaling reported at `--threads 1` and default, GPU at `--gpu on/off` on the same binary; results cross-checked (same checksum) across the three.
7. Inputs arrive via `File.read_bytes` → `Array<U32>` (or a seeded generator), never as source literals.
8. `BEND_NO_TELEMETRY=1` and absolute `~/.bend/bin/bend`; version pinned in the report.
9. Sequential code is tail-recursive (loops); non-tail recursion only along fork trees.
10. Any `@unsafe` is justified in a comment (it only disables the termination check).

## 5. Backends

| Target | Status here | Notes (cite) |
|---|---|---|
| C (CPU) | **Works.** 10 threads default; `--threads N` | Fork-join pool, 2 GiB mmap'd stack per worker with guard page (`comp.ts:4629-4639`); arena reserved as 8 TiB `MAP_NORESERVE`, halving down to 8 GiB if the reservation fails (`comp.ts:5063-5104`) — RSS stays proportional to live data (montmul 15 MB, 3×2^24 U32 arrays 203 MB). |
| Metal (macOS) | **Works on the M4 mini.** `bend f.bend -o f` builds `f.gpu` (MTLBinaryArchive) in the same 5–6 s | Runtime `newLibraryWithSource:` with `MTLMathModeSafe`; a missing/stale `.gpu` recompiles at launch ("compiling the GPU program", `comp.ts:4836-4853`). Default span 2 GB. |
| CUDA (Linux) | Untested here (no GPU) | NVRTC, `--gpu-architecture=sm_MM` from the device's compute capability, **no allow-list** (`comp.ts:4934-4951`) ⇒ sm_120 (RTX 5090) works iff the installed NVRTC (CUDA ≥12.8) accepts it; CUDA 13 branch exists (`comp.ts:4915-4921`). Needs `/usr/local/cuda` or `CUDA_HOME` with `include/nvrtc.h` at build time (`main.ts:256-258`); links `-lcuda -lnvrtc`. Cubin cached as `f.gpu` keyed by source hash. |
| JS | Works (`bend f.bend` uses it) | One thread, no `!`, `Nat` as BigInt; recursion-depth bugs (#798, #802). Dev-loop only. |

Issue tracker (2026-09-18, `gh issue list --state all --limit 100`: 23 open / 77 closed in the last 100; the Bend 2 issues are all ≥ #767, 2026-09-17+): relevant open — #804 array split/join copies, #791/#779 Nat-literal checker overflow, #792 IO receive effects eagerly allocate `max` and `_exit` on failure, #775 unused argument evaluated natively but skipped in run mode. Closed but instructive: #767 plain calls not parallel (fixed), #769 Homebrew clang `-fmodules`, #770 termination check is positional (shrinking arg first).

## 6. Ceilings and pitfalls (measured: `bend2/probe/limits.out.txt`)

- **Memory:** flat arena; OOM = `out of memory: run again with a bigger span, as in --gpu 8GB` and `_exit(1)` (`comp.ts:162-166`). `Array.new(U32, 30n, 7)` (2^30 = 4 GB) 568 ms; 2^31 1.06 s; **2^32 → `an array past the deepest block class 31`**. 2^26-cell list: 2.1 s, 2.7 GB. Refcount saturates at 2^24 shares (`ERR_RFCS`); `Array` is non-reusable anyway (§ below, GUIDE.md:183) — a 2^18-point G1 proving-key array is 32 MiB, thread it through owned indexed reads.
- **Recursion:** no C stack — non-tail recursion 2^26 deep on the host is fine (241 ms at 2^24). On the device each lane has a 2^11-word stack: keep GPU leaves tail-recursive or shallow.
- **Termination checker:** the shrinking argument must come first and be a pattern part (`1n+p`); U32 cannot drive a loop (no `1+p` pattern) — all counters are `Nat`, converted with `U32.from_nat` at use. Mutual recursion is a compile error; the stage-def idiom returns state and the loop recurses on it.
- **Affinity:** every variable used twice needs `+` (incl. `+t1 : Nat <- IO.now()`, `case 1n++p`); `Type`-kinded values (arrays, closures, files) can never be `+`.
- **Compile-time:** 1.8k-line fully unrolled `montmul.bend` (2.9k SSA lets in one def) type-checks + compiles + builds Metal in 6 s — large generated straight-line code is fine. Whole program is one C file (no separate compilation).
- **Big Nat literals crash the checker** (≥10000n). **Metal per-call overhead ~55 ms**; first call ~0.4 s. **Metal times are noisy** (same run 76 ms / 392 ms) — report medians of ≥3.
- Nothing found that blocks MSM/NTT at 2^20: 2^20 Fr elements × 16 limbs = 64 MB as `Array<U32>` (index `16·i + j`), well under the 2^31-cell cap and the 2 GB Metal span.

## 7. How we will write it

**Representation.** Fr/Fq as 16 little-endian 16-bit limbs in `U32`, R = 2^256, kept in Montgomery form. In flight: a `type Fr is Data: Fr{+l0: U32, …, +l15: U32}` record (16 words; all limbs come out reusable). At rest: `Array<U32>` with 16 slots per element (`a[16*i + j]`), packed 4 B/limb; points as parallel arrays (X, Y, Z / or one 48-slot stride). Constants (p limbs, `n0' = -p^{-1} mod 2^16 = 0xFFFF` for Fr (p ≡ 1 mod 2^16), R² mod p) inlined as U32 literals by the generator.

**Montgomery mul (type-checked, 1000/1000 correct — `bend2/probe/montmul.bend`, emitted by `gen_montmul.py`):**

```python
type Fr is Data:
  Fr{+l0: U32, +l1: U32, ..., +l15: U32}

def mont(a: Fr, b: Fr) -> Fr:
  match a b:
    case Fr{a0, ..., a15} Fr{b0, ..., b15}:
      # CIOS, outer i over b's limbs, fully unrolled SSA; one cell per line:
      +v1 = U32.mul(a0, b0)                 # s = t[j] + a[j]*b[i] + c   (exact in U32)
      +v2 = U32.and(v1, 65535)              # t[j] = s & 0xFFFF
      +v3 = U32.shrn(v1, 16n)               # c    = s >> 16
      +v4 = U32.add(U32.mul(a1, b0), v3)
      ...                                   # then m = (t0 * 65535) & 0xFFFF; s = t0 + m*p0; shift the row down
      ...                                   # final: d = t - p with borrow chain; keep_t = (t >= p) - 1
      Fr{U32.or(U32.and(t0, keep_t), U32.and(d0, U32.not(keep_t))), ...}  # branch-free select
```

Add/sub are the same 16-cell carry/borrow chains; `mont(x, R2)` converts in, `mont(x, Fr{1,0,…})` converts out. The loop-based `Array<U32>` variant (16 `a[i]` reads per row through stage defs) is the fallback if record-based code hits a compiler blind spot on the GPU.

**MSM (Pippenger), CPU and GPU shape — superseded plan; actual: `bend2/src/msm.bend` (fork tree of private bucket arrays, serial bucket join), results in `bend2/bench/msm_results.md`.** Windows of c bits (c = 12–16 at 2^20). Per window: (1) bucket accumulation as a fork tree over point ranges — `acc(d, lo, w)` splits the range, each leaf owns a **private `Array` of 2^c bucket points** initialised to ∞ and adds its 2^(20-d) points (owned, in place); the join adds bucket arrays element-wise (a balanced tree over bucket index, itself a fork tree); (2) bucket reduction as a parallel prefix over the 2^c buckets (a tree of `add` with running sums); (3) window combination sequential (≤22 doublings/adds). One `msm_window!(…)` per window on Metal; leaves must be equal-sized — never split on scalar values (divergence kills the fixed-placement scheduler).

**NTT (radix-2, size 2^20) — superseded plan; actual: `bend2/src/ntt.bend` (Stockham chunk tree), results in `bend2/bench/ntt_results.md`.** Iterative in-place is awkward (one owner per array, no shared mutation), so use the recursive DIT shape: `ntt(d, a: Array<U32>, twiddles)` splits even/odd into two *new* arrays (a gather pass, ~60 ms per 2^24 U32 measured), forks `l r = ntt(p, evens) ntt(p, odds)`, then a butterfly pass fused with the merge writes the output array; the top log2(cores) levels fork, deeper levels run sequentially in a leaf. Twiddles precomputed in Montgomery form in an `Array<U32>` indexed by `(k << level)`. Expect the data-movement passes, not the muls, to dominate: 2^20 × 20 levels ≈ 2^24 element moves ≈ 0.1–0.2 s on CPU from the gather numbers below. Bit-reversal is free in the recursive form.

## Measured on M4 (Mac mini, 10 cores, 16 GB, Metal; Bend 2.0.5, Apple clang 21)

| Probe (file) | Config | Result |
|---|---|---|
| hello (`hello.bend`) | `bend -o` compile / run | 0.66 s compile, prints; JS run mode 0.4 s |
| numeric (`numeric.out.txt`) | C target | `65535*65535=4294836225`, `65536*65536=0`, `4294967295+1=0`, `1<<32=0`, `7/0=0`, `7%0=7`; Nat 2^48 aborts; `10000n` literal crashes the checker |
| parallel sum 2^24, K=4 hash rounds/elt (`parallel.out.txt`) | seq loop | 157–159 ms |
| | fork tree FD=14, `--threads 1` | 152–159 ms |
| | `--threads 4` | 47–50 ms (3.2×) |
| | `--threads 10` | 26–28 ms (**5.7×**) |
| | `par!` with `--gpu off` | 24–26 ms |
| | `par!` on Metal | 64–102 ms (first call 400–500 ms) — GPU slower than 10 cores for 16M cheap leaves |
| arrays 2^20 (`arrays.out.txt`) | new / fill / idx / gather / sum | all ≤1 ms |
| arrays 2^24 | new / in-place fill / idx fill / gather `out[i]=src[idx[i]]` / sum | 8 / 4 / 20 / 62 / 2–3 ms; RSS 203 MB (3 × 64 MB) |
| io (`io.out.txt`) | 8 MB (2^21 LE U32) `File.read_bytes` 1 MB chunks → `Array<U32>` | 25–35 ms, sum32 matches Python; 0.5 MB: 3 ms; `/dev/stdin` works; argv rejected |
| montmul check (`montmul.check.txt`) | `uv run python check_montmul.py ./montmul 1000` | **1000/1000** match `a·b·R⁻¹ mod p` |
| montmul batch 2^16 (`montmul.out.txt`) | `--threads 1` / `--threads 10` / Metal | 8 ms / 2 ms / 57 ms |
| montmul batch 2^20 | `--threads 1` | 118 ms → **8.9 M mul/s** |
| | `--threads 10` | 26 ms → 40 M mul/s |
| | Metal (FD 12–20) | 57–61 ms → 18 M mul/s (overhead-bound) |
| montmul batch 2^24 | `--threads 1` | 1914 ms → 8.8 M mul/s |
| | `--threads 10` | 440 ms → **38 M mul/s** (4.4×) |
| | Metal FD=16 | 78 ms (78–101 range; one 223 ms outlier) → **~200 M mul/s**, checksum = CPU |
| montmul 2^24 × K=8 chained (134M muls) | `--threads 10` | 3317 ms → 40 M mul/s |
| | Metal FD=16 | 201 ms → **~670 M mul/s**, checksum = CPU |
| limits (`limits.out.txt`) | non-tail list build 2^24 / 2^26 | 241 ms / 2077 ms (2.7 GB) |
| | `Array.new(U32, d)` d=27/29/30/31/32 | 88 / 320 / 568 / 1062 ms / error `deepest block class 31` |

**First feasibility signal (superseded estimate):** a 2^20 MSM needs ~2^20 × ~10 field muls per point-add ≈ 10^7–10^8 mont muls ⇒ ~0.3–2.5 s on 10 CPU cores, ~0.1–0.5 s on Metal at the rates above, before data movement. Measured: 11.1 s on 10 CPU threads, tens of seconds on Metal (`bend2/bench/msm_results.md`) — the estimate missed the per-window work and the bucket join.
