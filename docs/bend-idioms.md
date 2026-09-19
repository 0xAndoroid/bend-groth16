# Bend idioms for the BN254 benchmark

**Checked 2026-09-18. Target: Bend 1 (`bend-lang 0.2.38`) + HVM2 (`hvm 2.0.22`), not Bend 2.**
Use native unsigned limbs, small arithmetic helpers, and balanced trees of independent field/point operations.
CUDA/RTX 5090 execution needs a hardware gate; this research did not install or execute either runtime.
All links below were accessed **2026-09-18**; issue dates distinguish historical reports from current status.

## 1. Version boundary and installation

| Component | Exact current observation | Consequence |
|---|---|---|
| Current Bend | **2.0.5** in the [distribution manifest](https://bend-lang.com/dl/latest.json) and [CLI source](https://github.com/bendlang/bend/blob/0b7e2b11c1054f5d0f4eb955cadb47997ef1115d/bend2/main.ts#L32); version commit **2026-09-17**, [38ad338](https://github.com/bendlang/bend/commit/38ad3382d8b611fa83bba769c15fa3612cce9fc7). | `HigherOrderCO/Bend` now redirects to `bendlang/bend`. Active development: inspected head `0b7e2b1`, **2026-09-18**. |
| Bend 1 | Crates.io **0.2.38**, published **2025-02-23 18:22:36 UTC**, not yanked; package source `58372e05fb96ec228cd09310f6a6418f1967a48f`. [Registry](https://crates.io/api/v1/crates/bend-lang), [manifest](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/Cargo.toml). | `hvm = "=2.0.22"` is pinned. Legacy repository is `HigherOrderCO/Bend1`; no later published crate found. |
| HVM2 | Crates.io **2.0.22**, published **2024-08-09 20:00:44 UTC**, not yanked; package source `349483954fe78a76fd420460ce0c8a8259a44c25`. [Registry](https://crates.io/api/v1/crates/hvm), [manifest](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/Cargo.toml). | This is the runtime used here. `HigherOrderCO/HVM` now redirects to **HVM1**; use explicit HVM2 URLs. |
| HVM3 / HVM4 | HVM3 exists, calls itself WIP, Cabal version **0.1.0.0**, head `fba2e9c` dated **2026-01-29**; its stated Bend-target ambition is not evidence of integration. HVM4 also exists and describes itself as pre-launch. [HVM3 README](https://github.com/HigherOrderCO/HVM3/blob/fba2e9c82faf6e2f019c9ecea94c32f19a8b7820/README.md), [Cabal](https://github.com/HigherOrderCO/HVM3/blob/fba2e9c82faf6e2f019c9ecea94c32f19a8b7820/HVM.cabal), [HVM4](https://github.com/HigherOrderCO/HVM4). | Neither replaces HVM2 in `bend-lang 0.2.38`; no GitHub releases returned for HVM3. |

**Activity:** Bend1 head `8144536` (**2026-07-07**) is an activity-only commit; preceding change is a README correction (**2025-06-03**). HVM2 head `6542760` is **2024-08-21**. Their September 2026 repository `pushed_at` values do not demonstrate new runtime work. The inspected `src/` trees exactly match the published crates. [Bend1 history](https://github.com/HigherOrderCO/Bend1/commits/main/), [HVM2 history](https://github.com/HigherOrderCO/HVM2/commits/main/).

`gh release list -R HigherOrderCO/Bend`, `-R HigherOrderCO/Bend1`, `-R HigherOrderCO/HVM`, and `-R HigherOrderCO/HVM2` returned no releases; current tags were also empty for the redirected Bend/HVM repositories. Use registry publication dates above, not an invented GitHub release date.

**Current Bend 2 is a different language/runtime:** native `U32`/`F32` plus inductive `Nat`; owned, in-place arrays; C/Metal/CUDA/JS targets; explicit balanced parallel calls; suffix `!` dispatches to GPU. The current [site](https://bend-lang.com) installs it, not HVM2. No `U64`/`I64`/`F64` in its stated type set. Its [README](https://github.com/bendlang/bend/blob/0b7e2b11c1054f5d0f4eb955cadb47997ef1115d/README.md#limitations) explicitly rejects Bend1/HVM compatibility; [guide](https://github.com/bendlang/bend/blob/0b7e2b11c1054f5d0f4eb955cadb47997ef1115d/guide/GUIDE.md#parallelism). Do not import its syntax, array claims, or benchmarks into this target.

### Reproducible legacy recipe

```sh
cargo +stable install hvm --version 2.0.22 --locked
cargo +stable install bend-lang --version 0.2.38 --locked
hvm --version
bend --version
```

Both manifests declare Rust **1.74** minimum; **no nightly requirement**. Use current stable with the lockfile, a C11 compiler, and Linux/macOS (Windows: WSL). Install the intended CUDA toolkit and expose its `nvcc` **before** building HVM; rebuild with the same command plus `--force` after adding CUDA. `CUDA_HOME` controls CUDA library search. C compilation failure can leave an installed HVM without C support; successful installation alone is not the execution gate. [Build script](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/build.rs), [legacy installation guide](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/GUIDE.md#installation).

For comparison only, current Bend2 uses `curl -fsSL https://bend-lang.com/install.sh | sh`, Bun, and clang rather than Cargo/HVM. The launcher auto-updates unless `BEND_NO_TELEMETRY=1`; do not let it shadow the pinned `bend`. [Installer](https://bend-lang.com/install.sh), [Bend2 build tool](https://github.com/bendlang/bend/blob/0b7e2b11c1054f5d0f4eb955cadb47997ef1115d/bend2/main.ts#L213).

## 2. Numbers: the field-arithmetic constraint

| Legacy native type | Representation / syntax | Relevant operators |
|---|---|---|
| `u24` | 0 through 16,777,215; `7`, `0xff`, `0b11` | `+ - * / %`, comparisons, `& \| ^`, `<< >>` |
| `i24` | Two's complement, −8,388,608 through 8,388,607; **`+7` is signed**, `7` is unsigned | Arithmetic, comparisons, `& \| ^`; no signed shift case in the runtime |
| `f24` | f32-like exponent, 15 stored fraction bits (16 significant bits); `1.0` | Arithmetic/remainder, comparisons, `**`; math builtins |

No native `u32`, `u48`, `u64`, wide integer, carry, or high-multiply operation exists in this toolchain. An IO “u48” is **two u24 values**, not a fourth number type. `== != < > <= >=` return `u24` 0/1; integer `/` is quotient, `%` remainder; signed division truncates toward zero. `**` is floating exponentiation, not integer exponentiation. Use `x ^ 0xffffff` for unsigned 24-bit complement. [Numeric reference](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/native-numbers.md), [syntax operator table](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/syntax.md#numbers-and-infix-operations).

**Arithmetic semantics:** unsigned arithmetic results are truncated to 24 bits by number/port packing; `+`, `-`, `*` therefore wrap modulo `2^24`. Rust explicitly uses wrapping integer operations. Unsigned shifts mask the count with **31**, not 23: a shift by 32 behaves like zero, and shifts 24–31 discard all u24 bits. Avoid division/remainder by zero: Rust panics; C/CUDA provide no portable result. C signed multiplication uses `i32` intermediates and can overflow before 24-bit packing, so do not base field arithmetic on signed overflow. Never mix numeric kinds implicitly: the runtime can reinterpret one operand's bits. [Rust numeric evaluator](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.rs#L237), [C numeric evaluator](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.c#L499).

### Exact 24 × 24 → 48 without high-multiply

Original Bend1 sketch; return order `(low24, high24)`. Every temporary fits u24, including `c <= 12284`.

```bend
def mul_wide(a: u24, b: u24) -> (u24, u24):
  a0 = a & 4095
  a1 = a >> 12
  b0 = b & 4095
  b1 = b >> 12
  p0 = a0 * b0
  p1 = a0 * b1
  p2 = a1 * b0
  p3 = a1 * b1
  c = (p0 >> 12) + (p1 & 4095) + (p2 & 4095)
  lo = (p0 & 4095) | ((c & 4095) << 12)
  hi = p3 + (p1 >> 12) + (p2 >> 12) + (c >> 12)
  return (lo, hi)
```

Four narrow products plus split/carry work; **`(a * b) >> 24` cannot recover discarded bits**. Algebra checked against arbitrary-precision multiplication on 49 boundary pairs and 10,000 deterministic pairs; this checks the arithmetic, not Bend execution.

### Chosen limb scheme and cost estimate

**Fr and Fq: 22 little-endian limbs, radix `B=4096`, Montgomery `R=B^22=2^264`.** Canonical 254-bit values have at most two significant bits in limb 21. Keep separate modulus, `n0 = -p[0]^-1 mod B`, `R mod p`, and `R² mod p` constants for the two fields. One multiply-add cell is safe because

```text
(B−1)² + (B−1) + (B−1) = B²−1 = 2^24−1
  a*b       t       carry
```

Use two carry-normalized sweeps per CIOS round (`a * b[i]`, then `m * p`), **not** a sum containing both products before normalization. Carry propagation is serial inside one field product; parallelize across field products. An 11×24-bit representation saves storage but each wide product needs four narrow products and more carry handling; start with 22×12, benchmark 11×24 only against a measured bottleneck. Do not silently change radix after constants/serialization are fixed.

For the simple 22-round CIOS schedule: `2n²=968` MAC cells; each has multiply, two adds, mask, shift. Including `m=(t0*n0)&4095`: **990 narrow multiplies, about 4,884 scalar operations**, before top-limb handling and final subtraction. Bend emits two `OPER` nodes for a two-variable operation and one when a literal operand is partially applied; this yields **about 7,810 OPER interactions** for those cells with dynamic operands and literal masks/shifts. Calls, duplication, tuple wiring, matching and erasure cost extra. **Planning estimate: 20k–50k total interactions per Montgomery multiply, not a measurement or bound**; replace it with `-s` counts from the implemented kernel. [Operator lowering](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/fun/term_to_net.rs#L180), [OPER rule](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.rs#L796).

## 3. Backends, limits, and the RTX 5090 gate

| Bend1 command | Actual target in 0.2.38 | IO |
|---|---|---|
| `bend run-rs file.bend -s` | Single-threaded Rust reference evaluator (`hvm run`) | No host-effect dispatcher |
| `bend run file.bend -s` / `bend run-c file.bend -s` | **C interpreter**, multi-threaded | Yes |
| `bend run-cu file.bend -s` | CUDA interpreter, if HVM was built with nvcc | Host-dispatched IO exists |
| `bend gen-c file.bend` | Standalone C with compiled calls | Included |
| `bend gen-cu file.bend` | Standalone CUDA; **still embeds interpreted evaluation**, compiled-call path disabled | Included |

`bend run` is **not Rust** in this release. Also distinguish Bend's command names from HVM's. [Bend CLI](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/main.rs#L50), [HVM CLI/code generation](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/main.rs#L23).

**CPU threads:** build script chooses `TPC=2^floor(log2(num_cpus::get()))`; 12 visible logical CPUs means 8 workers, not all 12. `run-c` fixes this at installation; `gen-c` chooses it on the generation host. No runtime thread-count environment variable or CLI switch appears in the inspected HVM2 source. For generated C, compile with `-DTPC_L2=k` (the default is guarded by `#ifndef`); for `run-c`, change/rebuild its build-time setting. Do not reuse binaries generated on another machine without recording TPC. [Build selection](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/build.rs#L1), [C configuration](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.c#L40).

| Fixed resource | C | CUDA |
|---|---|---|
| Global nodes / variables | `2^29` each; 8-byte node + 4-byte variable arrays | Same counts; 29-bit locations, not growable arrays |
| Redex storage | `HLEN=2^16` high-priority/thread; `RLEN=2^24` low-priority/thread | Two 256-entry bags/thread; two global arrays of `128*128*256*3` pairs |
| Workers | Compile-time TPC | `TPB=128`, `BPG=128`: 16,384 threads; fixed, not GPU-autotuned |
| Local CUDA net | — | 8,192 nodes + 8,192 variables = **96 KiB dynamic shared memory/block** |
| Definition storage | 4,095 nodes and redex pairs/definition | 64 nodes and redex pairs/definition |
| Book / result traversal | 16,384 definitions; printer has `Port stack[4096]` | Same definition count and printer stack length |

Constants, not stale explanatory comments: [C storage](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.c#L121), [CUDA storage](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.cu#L116).
Derived array reservations: C approximately **6 GiB + 128 MiB × TPC**, plus book/thread storage; CUDA approximately **6.1875 GiB**, plus book/context/driver costs. These are allocation sizes, **not peak resident-memory measurements**. Free VRAM alone does not remove per-thread allocation partitions or shared-memory limits.

No language-level recursion-depth constant: reductions use work bags. Practical limits include live-net space, compiler/readback host stacks and the fixed printer stack; “unrestricted recursion” is not an unlimited-resource guarantee. CUDA's 64-node cap is **per lowered definition**, not 64 recursion levels. It is checked by default; never bypass `-Ocheck-net-size` to make a large kernel “work.” Split helpers and verify emitted definitions. [Size checker](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/hvm/check_net_size.rs), [actual compiler defaults](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/lib.rs#L432).

### CUDA status: available source; Blackwell not certified here

HVM2 ships C/CUDA sources and historical working RTX 4090 benchmarks; its README calls CUDA less stable than C. No source-supported claim that all CUDA execution broke at a particular version was found. [Runtime status](https://github.com/HigherOrderCO/HVM2/blob/654276018084b8f44a22b562dd68ab18583bfb5b/README.md#usage).
RTX 5090 is **compute capability 12.0**; CUDA **12.8** introduced native `sm_120` compilation. HVM2's generic “CUDA 12.x” guidance predates it. Old binaries need compatible PTX or a rebuild; the build script does not select `sm_120` explicitly. [NVIDIA GPU table](https://developer.nvidia.com/cuda/gpus), [CUDA 12.8 features](https://docs.nvidia.com/cuda/archive/12.8.0/cuda-features-archive/index.html), [PTX compatibility](https://docs.nvidia.com/cuda/blackwell-compatibility-guide/index.html).

The 96 KiB dynamic request is below Blackwell CC12.0's 99 KiB block limit, but static shared data/register pressure also count; **this is feasibility evidence, not a successful launch**. [NVIDIA limits](https://docs.nvidia.com/cuda/blackwell-tuning-guide/), [HVM launch setup](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.cu#L2332).
GPU runs must record toolkit/driver, build flags, `sm_120` or retained PTX, a scalar-correctness run, a branching tree run, peak memory, and field-vector parity against Rust/C. An explicit generated-source attempt is `nvcc -O3 -arch=sm_120 kernel.cu -o kernel`; its success is still unverified here. Search of HVM1/HVM2/Bend issue histories found no `5090` or `sm_120` result.

## 4. Parallelism idioms

HVM2 reduces active pairs of interaction-net nodes. Independent redexes can run concurrently; the runtime schedules reductions rather than a source-level loop onto one CUDA thread. Dependencies still impose span, and extra copying/reductions still cost work. The compiler gives branching recursive calls priority annotations for GPU scheduling. [HVM2 paper, scheduling](https://github.com/HigherOrderCO/HVM2/blob/654276018084b8f44a22b562dd68ab18583bfb5b/paper/HVM2.typst#L953), [priority pass](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/hvm/add_recursive_priority.rs).

| Shape | Expected behavior |
|---|---|
| Two independent recursive subtrees | Parallel branches; balanced work gives logarithmic fork/join depth |
| Tree map / associative tree fold | Independent leaves/subreductions; good default for MSM/NTT batches |
| Accumulator where step `i+1` consumes step `i` | Serial dependency; renaming it `bend` does not change that |
| List traversal / list fold | Linear spine; map's expensive head computations can overlap, but traversal exposes work sequentially |
| Repeated lookup of a shared input tree | Lookup paths plus demanded duplication; not free shared-memory loads |

`Tree(T)` has `Node { ~left, ~right }` and `Leaf { value }`. `fold` recursively transforms `~` fields before the node case uses them. The following is an original **Bend1 syntax sketch**, not a runtime-checked fixture; source forms match the [tree example](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/examples/gen_tree.bend) and [fold documentation](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/FEATURES.md#folding-and-bending).

```bend
def indices(d: u24, x: u24) -> Tree(u24):
  bend d, x:
    when d != 0:
      return Tree/Node(fork(d - 1, x * 2), fork(d - 1, x * 2 + 1))
    else:
      return Tree/Leaf(x)

def map_square(t: Tree(u24)) -> Tree(u24):
  fold t:
    case Tree/Leaf:
      return Tree/Leaf(t.value * t.value)
    case Tree/Node:
      return Tree/Node(t.left, t.right)

def tree_sum(t: Tree(u24)) -> u24:
  fold t:
    case Tree/Leaf:
      return t.value
    case Tree/Node:
      return t.left + t.right
```

`indices(d,0)` makes `2^d` leaves in index order; stay within u24 index range. For arbitrary N, pad to the next power of two with the operation's identity, or split counts into `floor(N/2)` and the remainder; handle N=0 explicitly. For imported data, assemble balanced chunks once, outside timed kernels; repeatedly finding list midpoints is not a parallel input representation.

**Scan:** upsweep a balanced tree, retaining each subtree with its total; downsweep with incoming prefix `p`: left gets `p`, right gets `combine(p,left_total)`. Emit each leaf's incoming prefix (exclusive scan). O(N) combines, O(log N) dependency depth; reverse directions for suffix scan. Store totals once and consume branches; recomputing them or copying a whole retained tree at each split loses that bound. The stateful `map_sum` example in FEATURES propagates ancestor state; it is not an in-order prefix scan across all leaves.

### Semantic traps

1. **`!` is not strictness syntax in Bend1.** `!x` creates a tree leaf, `![a,b]` a tree node. HVM IR's `&!` marks a priority redex; Bend2's `f!(x)` has a different GPU meaning. [Bend1 tree literals](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/syntax.md#tree-literals).
2. Use numeric primitives for limbs/counters, not Church/Peano arithmetic. Normal ADTs are lambda-encoded, whereas tuples and native numbers are not; additional uses of a value insert duplication. Copying demanded large structures/closures can dominate arithmetic. `use` substitutes syntax; captured variables can still be duplicated. [Encoding and duplication](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/FEATURES.md#some-caveats-and-limitations).
3. Use `match`/`switch`/`fold`/`bend` to guard recursion. Hand-written eager lambda recursion can expand forever, even beneath an apparent branch; retain match linearization and combinator floating. [Lazy definitions](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/lazy-definitions.md).
4. `$x` is an unscoped wire, not shared mutable state; it needs one binder and one use within a function. Avoid scopeless lambdas/manual superpositions in field kernels. [Scopeless-lambda rules](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/using-scopeless-lambdas.md).
5. Eta-equivalent printed lambdas need not match textually; more eta reduction can hurt GPU scheduling. 0.2.38 enables eta for C but disables it for CUDA/unknown targets. The options document's default table is stale: trust [CLI target override](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/main.rs#L195) and compiler defaults, not blanket `-Oall`.

## 5. Inputs, outputs, and source size

| Input route | What exists | Use here |
|---|---|---|
| Command-line terms | Positional arguments after the file are parsed as **Bend functional terms** and applied to the entrypoint, not a conventional string `argv`. | Small dimensions/seeds; quote compound terms, e.g. `bend run-c f.bend '42'`. [Parser](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/main.rs#L86). |
| Files | `IO/FS/open`, `read`, `close`, `read_file`, `read_to_end`; bytes represented as `List(u24)`, errors as `Result`. `read_to_end` requests 1,048,576-byte chunks. | Binary field/point data, decoded into trees before the measured computation. [Builtins](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/fun/builtins.bend#L398). |
| Stdin | `IO/FS/STDIN=0`, `IO/FS/read`, `IO/input`; stdout/stderr handles 1/2. | Small interactive input or a separately timed import stage. [IO reference](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/builtins.md#io). |
| Embedded `.bend` | Generate literal tuples/trees or small top-level chunk definitions; no bulk-data compiler bypass. | Tiny deterministic fixtures, not the default proving-key transport. |

IO works through C's host dispatcher and CUDA's **host-side** `do_run_io`/`io_read`; CUDA does not issue filesystem syscalls inside a device kernel. Each IO action resumes normalization, so byte-at-a-time IO can cause repeated launches and transfers. Rust's reference `run` only normalizes the net, with no equivalent IO loop. [C dispatcher](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/run.c#L740), [CUDA dispatcher](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/run.cu#L857), [Rust runner](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/main.rs#L160).

Generated input is source code: parsing, lowering, definition storage and C/CUDA compilation all scale with it. There is **no established safe maximum `.bend` byte count**. The 4,095/64-node definition limits and 16,384-definition book are concrete caps, including compiler-generated definitions. Splitting millions of embedded limbs into small functions can simply hit the book cap next. The radix example already splits its 24 bit-insertion steps over three functions for CUDA. [Radix source](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/examples/radix_sort.bend).

Keep final output compact: a proof/verification result or bounded diagnostics, not the whole work tree. Bend writes a fixed `.out.hvm` in the current directory when invoking HVM: **concurrent runs need distinct working directories**. Output parsing can obscure runtime crashes. [Subprocess/readback path](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/src/lib.rs#L221).

## 6. Performance ceilings and actual examples

**No O(1) mutable arrays in Bend1.** `xs[i]` is Map syntax, not list indexing. Builtin Map is a binary trie over u24 keys; get/set follow the key bits, rebuilding the accessed path and returning ownership. A balanced dense tree gives O(log N) positional access; lists give O(N). Consume subtrees and return updated structures rather than duplicating a whole container for each lookup. This does **not** describe Bend2's owned arrays. [Map representation/API](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/docs/builtins.md#map).

Treat interaction count as **work**, dependency depth as **span**, and elapsed time/memory as separate measurements. Native u24 ops are cheap relative to lambda arithmetic but still create reductions; ADT constructors, copying, matching, calls and erasure all contribute. GPU throughput depends on redex shape, divergence and memory, not only the count. Do not divide a field kernel's count by an unrelated best-case MIPS number. [HVM2 execution/scheduling analysis](https://github.com/HigherOrderCO/HVM2/blob/654276018084b8f44a22b562dd68ab18583bfb5b/paper/HVM2.typst).

**Measure external monotonic wall time too:** CUDA's reported `TIME` divides host `clock()` ticks by `CLOCKS_PER_SEC`; C uses `CLOCK_MONOTONIC`. Both differ in scope from whole-process timing. Do not assume backend `TIME` fields are identical clocks. [CUDA timer](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.cu#L2338), [C timer](https://github.com/HigherOrderCO/HVM2/blob/349483954fe78a76fd420460ce0c8a8259a44c25/src/hvm.c#L296).

| Upstream example/evidence | Size | Published result / limitation |
|---|---|---|
| [Bend1 README bitonic sorter](https://github.com/HigherOrderCO/Bend1/blob/814453670d0e0d6777c1313c972764dba0491b7f/README.md#bitonic-sorter-benchmark) | `d=20`: **1,048,576** generated leaves, then sort and sum | M3 Max Rust **12.15 s**, M3 Max C **0.96 s**, RTX 4090 CUDA **0.21 s**. Upstream historical numbers; versions, flags and full methodology are not pinned there. Not fresh 0.2.38 measurements. |
| [Checked-in bitonic example](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/examples/bitonic_sort.bend) | `d=18`: **262,144** leaves | Different size than the README timing; do not combine them into one measurement. |
| [Checked-in radix example](https://github.com/HigherOrderCO/Bend1/blob/58372e05fb96ec228cd09310f6a6418f1967a48f/examples/radix_sort.bend) | `gen 4`: **16** leaves, 24-bit keys | No timing in the file. It stores presence, so duplicate keys collapse; it is not a general multiplicity-preserving sort. No defensible large-N radix timing found in the inspected sources. |
| [HVM2 paper](https://github.com/HigherOrderCO/HVM2/blob/654276018084b8f44a22b562dd68ab18583bfb5b/paper/HVM2.typst#L953) | Synthetic tree-map / sorting shapes | Peak **74,000 MIPS** on RTX 4090 is a tree-map throughput claim, not BN254 throughput or a memory-capacity result. |

The sort examples validate scheduling shapes, not large-integer arithmetic. Their terminal sum alone cannot detect incorrect ordering, and a u24 sum can wrap. Later benchmarks must validate outputs against the reference, separately from timing.

## 7. Known failures: evidence and status

Legacy issues were bulk-closed during the **2026-09-16** repository move, not necessarily fixed. They now live under `bendlang/bend` and `HigherOrderCO/HVM1`, even when discussing Bend1/HVM2. The Bend [closure notice in #632](https://github.com/bendlang/bend/issues/632) says to reopen applicable issues in Bend1. Do not infer correctness from a zero-open-issues count.

| Report | Version/date evidence | Current interpretation |
|---|---|---|
| [Bend #632](https://github.com/bendlang/bend/issues/632): large input/output failure | Opened **2024-07-15**: Bend **0.2.36**, HVM **2.0.21**, embedded list near `2^19` elements; direct HVM segfault. **2024-10-29** comment reports output truncation near 20,472 characters. | Closed **not planned**, **2026-09-16**; historical reproductions, not retested on our pins. Avoid giant single definitions/results. |
| [HVM #314](https://github.com/HigherOrderCO/HVM1/issues/314), [#417](https://github.com/HigherOrderCO/HVM1/issues/417) | **2024-05-20** illegal CUDA access in bitonic sort on RTX 3050 Ti Mobile/CUDA 12.4; **2024-08-20** shared-memory configuration work. | Both closed **not planned**, **2026-09-16**. GPU memory/layout constraints remain in source. |
| [Bend #538](https://github.com/bendlang/bend/issues/538), [HVM #440](https://github.com/HigherOrderCO/HVM1/issues/440) | **2024-06-02** WSL CUDA hang, 12.4/12.5; **2025-07-28** HVM **2.0.22** install picked CUDA 11.8 in a mixed 11.8/12.6 setup. | Closed **not planned**, **2026-09-16**. Check actual nvcc/toolkit, not only `nvidia-smi`. No proven universal “CUDA broken since X” conclusion. |
| [HVM #370](https://github.com/HigherOrderCO/HVM1/issues/370): CUDA/Rust disagreement | **2024-06-04**; maintainer identifies IO expansion bug, fixed by [PR #401](https://github.com/HigherOrderCO/HVM1/pull/401) on **2024-07-03**. | Closed completed before **2.0.22**; not an unresolved regression claim. Preserve cross-backend parity checks. |
| [Bend #634](https://github.com/bendlang/bend/issues/634): GPU slowdown | **2024-07-17**, discussion through **2024-09-04**: eta changes reduced sorter throughput roughly 12,000→6,000 MIPS. | Specific case closed completed after disabling problematic eta behavior; current target-dependent default matters. Fewer interactions need not mean lower wall time. |

**Wrong-result caution:** [Bend #504](https://github.com/bendlang/bend/issues/504), **2024-05-26**, Bend 0.2.21/HVM 2.0.17: initial lambda-printing cases were explained as eta/lazy-reference/readback differences; a later higher-order duplication case was invalid in Bend. Do not cite every “wrong reduction” title as a confirmed arithmetic bug. Keep field kernels first-order and compare numeric results, not lambda printouts.

**Current Bend2-only issues, not Bend1 regressions:** open [#785](https://github.com/bendlang/bend/issues/785) (**2026-09-18**, 2.0.5) reports generated 1,000/2,000 sequential IO statements compiling in **11.6/72.6 s**, failure near 4,000; open [#791](https://github.com/bendlang/bend/issues/791) (**2026-09-18**) reports checker stack failure for `10000n`. These make an unexamined switch to Bend2 risky too; they do not establish legacy compiler complexity.

## 8. How we will write it

### Field elements and Montgomery kernel

Use fixed native tuple groups for 22 u24 limbs; destructure and rebuild them explicitly. Small native tuples avoid tagged-list traversal and object/lambda encodings in the hot arithmetic path. Fq2 is a pair of Fq elements; projective points use coordinate triples. Use balanced `Tree(Fr)` / `Tree(Point)` for **batches**, not a general Map per field element. A List may simplify a reference kernel, but copying/traversal then belongs in its cost report. Tradeoff: positional tuple code is less readable; fixed size, lower matching overhead, and CUDA's small-definition cap favor short named limb-group helpers, not one fully unrolled 22×22 definition.

Original Bend1 **partial sketch**; `add_row12`, `low12`, and `drop_low12` below name required tuple operations, not shipped builtins:

```bend
def mac12(a: u24, b: u24, t: u24, carry: u24) -> (u24, u24):
  z = a * b + t + carry
  return (z & 4095, z >> 12)

def mont_round(a, bi, t, modulus, n0):
  t = add_row12(t, a, bi)
  m = (low12(t) * n0) & 4095
  t = add_row12(t, modulus, m)
  return drop_low12(t)
```

`add_row12` traverses 22 normalized limbs with `mac12`, retaining overflow in **two extra scratch limbs**; it must not discard the top carry. Start scratch at zero, call `mont_round` for `b[0]` through `b[21]`, then subtract the modulus once when needed for canonical inputs. `drop_low12` is the exact division by B after cancellation of the low limb. Inputs represent `aR,bR`; output represents `abR`. Convert at boundaries with Montgomery multiplication by `R²` / ordinary one. The tuple plumbing and borrow/top-limb handling remain implementation work; this sketch is not a complete tested multiplier.

### MSM and NTT shapes

| Kernel | Shape to implement | Avoid |
|---|---|---|
| NTT over Fr | DIT: recursive even/odd decomposition, two independent transforms, then a tree zip of butterflies. DIF: butterflies first, then recurse into halves. Generate/partition twiddles alongside the same shape. Record ordering and root convention explicitly. | List-based repeated split/index; duplicating the whole twiddle/input tree per butterfly; assuming every stage is independent. |
| Pippenger MSM | Balanced tree of scalar/point chunks; each leaf forms local buckets. Merge corresponding buckets with point addition in a balanced tree reduction. Use projective Fq points inside the kernel. | One global accumulator/Map threaded through every point; one full dense bucket set per input point; duplicating the proving-key tree for every bucket. |
| Bucket weighting | Descending bucket suffix scan with group addition, then tree-reduce those suffix sums. Combine window results with the correct powers of `2^w`. | Sequential running-sum loop presented as parallel; treating field addition as point addition. |
| Batch inversions / scan | Product-tree upsweep, one inversion, downsweep of prefix/suffix products; define zero treatment. | One inversion per point, or recomputing subtree products at every node. |

These are design recommendations, not upstream performance claims. Start with bounded point chunks and a modest measured window; partial bucket storage is O(chunks × buckets) if dense. A sparse trie saves empty buckets but adds matching/path work. Choose with interactions **and** peak memory, not parallelism alone.

### Reviewer checklist — representation and arithmetic

1. Exact Bend/HVM versions recorded; no Bend2 syntax/APIs or accidental latest-site install.
2. Fr/Fq constants, Montgomery domain, endian order and limb bounds agree with reference vectors; no hidden u24 wrap or floating arithmetic.
3. Top carry, borrow, final subtraction and identity/zero cases checked; partial sketches replaced with actual code.
4. Field scalars use fixed native limbs; bulk work uses balanced trees; no repeated whole-structure duplication/indexing in hot paths.
5. CUDA size check passes on every lowered definition; helper splitting stays under the 16,384-definition book cap.

### Reviewer checklist — execution and measurement

6. Independent branches exist in the lowered computation; accumulator dependencies and scans are accounted for, not merely labeled parallel.
7. Rust/C numeric parity passes before CUDA claims; GPU build, launch, and correctness recorded on the actual target with TPC/TPB/BPG and memory settings.
8. Timing separates source generation/compilation, input conversion, runtime, output and validation; interactions, wall time and peak memory all reported; concurrent runs have separate directories.
