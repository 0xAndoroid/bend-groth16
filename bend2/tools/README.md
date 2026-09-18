# bend2/tools — JSON ⇄ Bend binary converters

Stdlib-only Python (`uv run python`). Format: [`../FORMAT.md`](../FORMAT.md) (frozen). Inputs are the
arkworks JSON from `groth16-ref gen|vectors` (see `ref/README.md`); paths may be absolute.

```sh
uv run python bend2/tools/export_bin.py data/<K>                  # -> data/<K>/bend/*.bin
uv run python bend2/tools/export_bin.py --vectors data/vectors    # -> data/vectors/bend/*.bin
uv run python bend2/tools/verify_bin.py data/4 data/18 --vectors data/vectors   # round-trip self-check, exit 1 on mismatch
BENDG_DATA=data/<K>/bend ./prove_bin | grep -E '^[ABC] ' | uv run python bend2/tools/proof_to_json.py -o proof.json --compare data/<K>/proof_ref.json   # drop the T timing lines
```

- `export_bin.py`: Fr/Fq → Montgomery (`x·2^256 mod p`) as 16×u32 words of 16-bit limbs; scalars (`k`,
  MSM scalars) and `a_canonical` stay canonical; infinity → all-zero words. `json.load`s `pk.json` once
  (K=18: 269 MB → 1.7 GB peak RSS). Output is deterministic (byte-identical across runs).
- `verify_bin.py`: re-reads every `.bin`, converts Montgomery → canonical and compares to the JSON integer,
  checks header counts/file sizes, rebuilds each R1CS row from the CSR, and cross-checks the Montgomery
  constant against arkworks' `a_mont` in `*_ops.json`.
- `proof_to_json.py`: Bend prover stdout (`A x y` / `B x0 x1 y0 y1` / `C x y`, canonical 0x hex; stdin or
  file) → arkworks `proof.json`; `--compare` prints `A/B/C: EQUAL|DIFFERENT` on stderr, exit 1 if any differ.

## Sizes and timings (Mac mini, Python 3.14)

| K  | pk_a | pk_b1 | pk_b2 | pk_h | pk_l | r1cs_{a,b,c} (each) | witness | total | export wall | verify wall |
|----|------|-------|-------|------|------|---------------------|---------|-------|-------------|-------------|
| 4  | 2.3 KB | 2.3 KB | 4.6 KB | 4.0 KB | 2.0 KB | 1.2 KB | 1.2 KB | 22 KB | 0.03 s | 0.0 s |
| 10 | 131 KB | 131 KB | 263 KB | 262 KB | 131 KB | 74 KB | 66 KB | 1.2 MB | 0.05 s | 0.0 s |
| 14 | 2.1 MB | 2.1 MB | 4.2 MB | 4.2 MB | 2.1 MB | 1.2 MB | 1.0 MB | 19.3 MB | 1.8 s | 0.5 s |
| 18 | 33.6 MB | 33.6 MB | 67.1 MB | 67.1 MB | 33.6 MB | 18.9 MB | 16.8 MB | 308.3 MB | 4.3 s (1.7 GB RSS) | 6.8 s |

Vectors: 10 files, 0.55 MB total (`msm_small_1024` / `ntt_small_1024` 197 KB each), 0.01 s.
Fixed-size files: `header.bin` 32 B, `pk_g1.bin` 384 B, `pk_g2.bin` 512 B, `rs.bin` 128 B, `proof_ref.bin` 512 B.
