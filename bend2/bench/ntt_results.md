# NTT bench (bend2/bench/ntt.bend)

M4 Mac mini (4P + 6E cores, Metal), Bend 2.0.5, Apple clang; medians of 3 runs; pseudo-random Fr inputs; the checksum (U32 sum of limb 0 over the output) agreed across all three configurations for every row. CPU rows use the module default fork depth `Ntt.fd(log2) = min(12, log2-1)` (2^fd chunks); Metal rows use FD=14 (clamped to log2-1 below 2^15) for fft/ifft/coset_fft and FD=12 for qap_h. Metal = `Ntt.<op>_fd!(...)`, one `!` per transform.

| op | size | `--threads 1` | 10 threads | Metal |
|---|---|---|---|---|
| fft | 2^10 | 3 ms | 3 ms | 62 ms |
| fft | 2^12 | 11 ms | 7 ms | 75 ms |
| fft | 2^14 | 32 ms | 15 ms | 114 ms |
| fft | 2^16 | 135 ms | 47 ms | 392 ms |
| fft | 2^18 | 566 ms | 158 ms | 1123 ms |
| fft | 2^20 | 1987 ms | 529 ms | 3381 ms |
| ifft | 2^10 | 5 ms | 3 ms | 66 ms |
| ifft | 2^12 | 11 ms | 7 ms | 76 ms |
| ifft | 2^14 | 40 ms | 16 ms | 116 ms |
| ifft | 2^16 | 183 ms | 56 ms | 420 ms |
| ifft | 2^18 | 517 ms | 135 ms | 1106 ms |
| ifft | 2^20 | 2155 ms | 542 ms | 3333 ms |
| coset_fft | 2^10 | 5 ms | 3 ms | 64 ms |
| coset_fft | 2^12 | 14 ms | 7 ms | 75 ms |
| coset_fft | 2^14 | 45 ms | 17 ms | 117 ms |
| coset_fft | 2^16 | 174 ms | 57 ms | 396 ms |
| coset_fft | 2^18 | 527 ms | 182 ms | 1015 ms |
| coset_fft | 2^20 | 2159 ms | 612 ms | 3360 ms |

`qap_h` (a, b, c evaluation vectors -> h coefficients: 3 ifft + 3 coset_fft + pointwise + coset_ifft):

| d | `--threads 1` | 10 threads | Metal |
|---|---|---|---|
| 2^11 (K=10) | 60 ms | 40 ms | 95 ms |
| 2^15 (K=14) | 493 ms | 181 ms | 245 ms |
| 2^19 (K=18) | 8836 ms | 2646 ms | 2220 ms |

Notes:
- Single-thread cost is ~90 ms per stage at 2^20 (2^19 butterflies; the Montgomery mul is ~2/3 of it). 10 threads give ~4x, in line with the pure-`Fr.mul` fork-tree ceiling measured on this 4P+6E part (`field_mul` 2^20: 116 -> 25 ms); with FD <= 6 (<= 32 tasks per stage) scaling collapses to <2x because tasks never migrate.
- Metal is 6-21x slower than 10 CPU threads for a single fft (`bench/bend2-macmini.json` `ntt.<k>.gpu/cpu_all`: 20.7x at 2^10, 7.6x at 2^14, 6.4x at 2^20; other transforms up to 22x): every stage allocates its output chunks on the device and each lane walks its chunk with 16-word reads/writes; the per-`!` dispatch (~55 ms) plus ~20 host-driven stage rounds dominate the small sizes. It only wins on `qap_h` at 2^19 (three independent pipelines in flight, 2.2 s vs 2.6 s). Not tuned further in this lane.
- Memory: a 2^20 transform peaks at ~870 MB RSS (input + per-stage output chunks; freed chunks are recycled by the arena but the RSS high-water mark stays).
