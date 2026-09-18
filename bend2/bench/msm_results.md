# bend2 MSM benchmark (Pippenger, `bend2/bench/msm.bend`)

M4 Mac mini (10 cores, 16 GB, Metal), Bend 2.0.5, `--gpu 8GB` span, medians of 3 (2^20 1-thread, G2 2^18 and
Metal ≥ 2^18: single runs). Points = `data/18/bend/pk_a.bin` (n ≤ 2^18), `pk_h.bin` (2^19 real points; 2^20 =
those points twice with different scalars); scalars = canonical `witness.bin` cycled. The affine result is
identical across `--threads 1`, 10 threads and `MODE=gpu` for every n (checksums in the campaign log).

Defaults (`Msm.pick_c` / `pick_fd`): window c = 8 below 2^18, c = 12 from 2^18; fork depth fd = min(4, log2 n − c)
(2^fd leaves, each with a private bucket array of all windows). Bucket join = (2^fd − 1) · windows · 2^c Jacobian
adds, which is why c = 8 (32 windows, cheap join) beats c = 12 (22 windows, 1.35 M-add join) up to 2^16.

## G1 (`MODE=cpu`, default c/fd)

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

## G2 (`MODE=cpu`, default c/fd)

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
