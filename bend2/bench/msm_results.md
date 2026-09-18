# bend2 MSM benchmark (Pippenger, `bend2/bench/msm.bend`)

M4 Mac mini (10 cores, 16 GB, Metal), Bend 2.0.5, `--gpu 8GB` span, medians of 3 (2^20 1-thread, G2 2^18 and
Metal ≥ 2^18: single runs). Points = `data/18/bend/pk_a.bin` (n ≤ 2^18), `pk_h.bin` (2^19 real points; 2^20 =
those points twice with different scalars); scalars = canonical `witness.bin` cycled. The affine result is
identical across `--threads 1`, 10 threads and `MODE=gpu` for every n (checksums in the campaign log).

**Input caveat (w5fix, 2026-09-18):** every table below was measured with a loader that allocated 2^18 G1 / 2^18 scalar
records while `pk_a.bin` and `witness.bin` hold 2^18 + 2, so the last two records overwrote the first two (G2: the whole
262146-record file was read into an n-record buffer) — timing is unaffected, but the "first n points" claim was false and the
checksums below do not match the fixed loader (`bench/msm.bend` now sizes every buffer from `header.bin`).

Defaults (`Msm.pick_c` / `pick_fd`): window c = 8 below 2^18, c = 12 from 2^18; fork depth fd = min(4, log2 n − c)
(2^fd leaves, each with a private bucket array of all windows). Bucket join = (2^fd − 1) · windows · 2^c Jacobian
adds, which is why c = 8 (32 windows, cheap join) beats c = 12 (22 windows, 1.35 M-add join) up to 2^16.

## v1 — G1 (`MODE=cpu`, default c/fd)

| n | c | 1 thread ms | 10 threads ms | 10-thread points/s | Metal ms | Metal points/s |
|---|---|---|---|---|---|---|
| 2^10 | 8 | 117 | 94 | 10.9 K | 1384 | 0.7 K |
| 2^12 | 8 | 412 | 348 | 11.8 K | 2722 | 1.5 K |
| 2^14 | 8 | 1835 | 604 | 27.1 K | 8502 (c=10) | 1.9 K |
| 2^16 | 8 | 4783 | 1896 | 34.6 K | 28327 (c=12) | 2.3 K |
| 2^18 | 12 | 14819 | 6547 | 40.0 K | 43349 | 6.0 K |
| 2^20 | 12 | 41514 | 20808 | 50.4 K | 106468 | 9.8 K |

Window comparison, 10 threads, fd = 4: 2^16 c=8 1896 / c=12 2465 / c=16 4493 ms; 2^18 c=8 6849 / c=12 6597;
2^20 c=8 27526 / c=12 21047. c = 16 needs the 8 GB span (16 × 256 MB bucket arrays).

## v1 — G2 (`MODE=cpu`, default c/fd)

| n | c | 1 thread ms | 10 threads ms | Metal ms |
|---|---|---|---|---|
| 2^10 | 8 | 372 | 208 | 6208 |
| 2^14 | 8 (Metal and 10-thread rows: c=10) | 3518 | 2304 | 40788 |
| 2^18 | 12 | — | 29300 | — |

## Reading the numbers

- Throughput is add-bound with heavy per-add overhead: 2^20 at c = 12 is ≈ 24.6 M point ops in 20.8 s = 1.2 M ops/s
  on 10 threads, vs 3.5 M/s for the bare `add_mixed` chain in `g1_add` — each bucket add also reads and writes a
  48-word Jacobian bucket through the stage-def readers and extracts a digit from the scalar array.
- CPU scaling is only 2× (1 → 10 threads at 2^20): with fd = 4 the top of the bucket join tree is one sequential
  pass over windows · 2^c buckets, and every ANode split of the point/scalar arrays copies (issue #804).
  More leaves (fd = 8) OOM-ed the 8 GB span at c = 12 (each leaf owns wpad · 2^c · 64 words).
- Metal is 5–15× slower than 10 CPU threads: a `!` with 16 leaves keeps 16 of 16384 lanes busy, and the
  private-bucket design cannot afford thousands of leaves (memory) nor a cheap join. A GPU-shaped MSM needs a
  sorted (per-bucket contiguous) layout with a shared read-only point array, which Bend 2 arrays (single owner,
  split = copy) do not offer; treat the Metal column as a correctness cross-check, not a speed result.

## v2 (2026-09-18): deeper fork, same layout — defaults c = 8 (< 2^20) / 10, fd = min(7, log2 n − c − 1)

Same M4 mini, Bend 2.0.5, `--gpu 8GB` span (2^20 OOMs the default span at every fd ≥ 6), single runs, **box
shared with a sibling lane burning one core** (v1 rows above were taken on a quiet box; v1 default re-measured
here for a fair pair). `bench/msm.bend` at this point read the whole `pk_a.bin` into a 2^18-record buffer; the two
extra records still wrapped onto records 0–1 (see the input caveat at the top), so the 2^16 checksums differ from v1's
for that reason and 2^18/2^20 were unchanged.

Root cause of v1's flat scaling: the scheduler has no work stealing, and `g1_add` itself scales only 2.1× at
FD = 4 (1167 ms) vs 4.6× at FD = 8 (528 ms, 1 thread 2423 ms, N = 20, loaded box). 16 leaves was the limit, not
the runtime or the per-add overhead (1-thread MSM already ran at 88% of the bare add chain).

| n | config | 1 thread ms | 10 threads ms | Metal ms | note |
|---|---|---|---|---|---|
| 2^16 | c=8 fd=7 (default) | 5352 | **1184** | 9711 | checksums equal (v1 default here: 3037) |
| 2^18 | c=8 fd=8 | — | 3679 / 3722 | 14909 | v1 default (c=12 fd=4) same box: 6875 |
| 2^18 | c=10 fd=7 | 24549 (v2-leaf, see below) | 3793 | — | c=10 fd=6 4724, c=10 fd=8 4451, c=12 fd=6 6009 |
| 2^20 | c=8 fd=8 | — | 13046 | — | |
| 2^20 | **c=10 fd=7 (default)** | — | **11087 / 11337** | — | was 20808 (v1 default, quiet box) → 1.85× |
| 2^20 | c=10 fd=8 | 59038 | 12316 | — | 1-thread and 10-thread checksums equal |
| 2^20 | c=12 fd=6 | — | 16051 | — | |
| 2^14 G2 | c=8 fd=5 (default) | — | 2049 | — | v1: 2304 |

Ops at 2^20: c=10 fd=7 = 26 · 2^20 adds + 127 · 26 · 1024 join adds = 30.7 M (v1 c=12 fd=4: 24.6 M); 11.1 s =
2.8 M ops/s on 10 threads (v1: 1.2 M/s), against 3.5 M/s for the bare `add_mixed` chain — so the remaining gap to
gnark (400 ms, `bench/gnark-macmini.json` `msm_g1.20`; ≈ 27.7×) is the add itself (0.67 M/s per core), not the MSM
structure. Bucket memory: 32 allocated windows × 1024 buckets × 64 words × 128 leaves = 1 GiB (plus join/input arrays).

Tried and rejected — **per-leaf window streaming** (leaf owns a point range and ONE 2^c-bucket array, streams the
range once per window, reduces the window with a running sum and folds Horner-style into one accumulator; leaf
result = 1 point, join = 1 add, no clones, no bucket join): 2^18 c=10 fd=7 **5846 ms** (1 thread 24549), c=8 fd=8
7780, c=12 fd=6 9874 — every leaf pays 2 · 2^c adds per window for the reduction (6.8 M at 2^18, equal to the
main work), whereas v1's bucket join costs one add per bucket per level and is shared across the tree. Killed in
favour of the 6-line defaults change. Not attempted (time box): windows-parallel leaves (needs W clones of the
128 MB point array: 2.8 GB at c=12; Bend has no shared read-only buffer), signed digits (needs carries across
windows, ~10% fewer adds), digit pre-extraction.

What limits us: no work stealing (leaf count must be ≥ ~128 to balance 10 cores), single-owner arrays (every
ANode split copies both halves, and a leaf can only see its own slice, so per-window ownership means cloning the
points W times), no GC (fd = 8 at c = 12 OOMs the 8 GB span), and Metal's 16384 lanes seeing only 2^fd tasks
(Metal 2^18 14.9 s vs 3.7 s CPU — still a checksum cross-check only).
