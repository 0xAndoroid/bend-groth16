# Bend 2 data interchange format (frozen 2026-09-18)

All binaries are little-endian, written by `bend2/tools/export_bin.py` from the arkworks JSON under `data/<K>/` and `data/vectors/`, read in Bend 2 via `File.read_bytes` into `Array<U32>` (see `docs/bend2-idioms.md` §3, `bend2/probe/io.bend`).

## Field elements
- BN254 Fr (r = 21888242871839275222246405745257275088548364400416034343698204186575808495617) and Fq (q = 21888242871839275222246405745257275088696311157297823662689037894645226208583).
- One element = **16 words × u32**, each word holding one **16-bit limb** (value < 2^16, upper 16 bits zero), little-endian limb order (word 0 = bits 0..15). 64 bytes per element.
- Values are stored in **Montgomery form with R = 2^256**: stored = x·2^256 mod p. (Bend keeps everything in Montgomery form; conversion out happens only when printing the proof.)
- Fq2 element (c0 + c1·u): c0 then c1 (128 bytes).

## Points
- G1 affine: X, Y (Fq, Montgomery) = 128 bytes. Point at infinity = X = 0, Y = 0 (all-zero words; (0,0) is not on y² = x³ + 3).
- G2 affine: X (Fq2), Y (Fq2) = 256 bytes. Infinity = all-zero.

## Files under `data/<K>/bend/`
- `header.bin`: u32 `num_constraints`, u32 `num_instance` (incl. the leading 1), u32 `num_witness`, u32 `domain_log2` (log2 of arkworks' evaluation domain size from pk.json `domain_size`), u32 `n_a`, u32 `n_b`, u32 `n_h`, u32 `n_l` (query lengths).
- `witness.bin`: `num_instance + num_witness` Fr elements (the full assignment z = [1, public..., private...]) in Montgomery form.
- `r1cs_a.bin`, `r1cs_b.bin`, `r1cs_c.bin`: u32 `nnz`; then `num_constraints + 1` u32 row offsets (CSR); then `nnz` entries of (u32 `col`, Fr `coeff` Montgomery) = 68 bytes each. Column indexes into z.
- `pk_g1.bin`: alpha_g1, beta_g1, delta_g1 (3 G1 affine).
- `pk_g2.bin`: beta_g2, delta_g2 (2 G2 affine).
- `pk_a.bin`: `n_a` G1 (a_query). `pk_b1.bin`: `n_b` G1 (b_g1_query). `pk_b2.bin`: `n_b` G2 (b_g2_query). `pk_h.bin`: `n_h` G1 (h_query). `pk_l.bin`: `n_l` G1 (l_query).
- `rs.bin`: r, s (2 Fr, Montgomery) from `proof_ref_rs.json` so the Bend prover can reproduce arkworks' exact proof.
- `proof_ref.bin`: A (G1), B (G2), C (G1) affine, Montgomery — for byte-equality checks.

## Test vectors under `data/vectors/bend/`
- `fr_ops.bin` / `fq_ops.bin`: u32 `count`; then per case 9 elements in order a, b, add, sub, mul, neg_a, inv_a, sq_a, and `a_canonical` (a NOT in Montgomery form — the raw integer in 16-bit limbs) to test from/to-Montgomery conversion. All others Montgomery form.
- `g1_ops.bin`: u32 `count`; per case: p (G1), q (G1), k (Fr, **canonical**, not Montgomery — it is a scalar), add (G1), double_p (G1), neg_p (G1), mul_pk (G1).
- `g2_ops.bin`: same layout with G2 points.
- `msm_small_<n>.bin` for n ∈ {8, 64, 1024}: u32 n; n G1 points; n scalars (Fr canonical); result G1.
- `ntt_small_<n>.bin` for n ∈ {8, 64, 1024}: u32 n; omega (Fr Montgomery); n_inv (Fr Montgomery); n coeffs (Montgomery); n evals (Montgomery); n icoeffs_of_evals (Montgomery).

## Proof output (Bend → verifier)
The Bend prover prints three proof lines to stdout: `A <x_hex> <y_hex>`, `B <x0_hex> <x1_hex> <y0_hex> <y1_hex>`, `C <x_hex> <y_hex>` — canonical (non-Montgomery) big-endian 0x hex — followed by timing lines `T <phase> <ms>` (`load evals qap msm_a msm_b1 msm_b2 msm_h msm_l total`). Filter `^[ABC] ` before `bend2/tools/proof_to_json.py`, which converts to the arkworks `proof.json` encoding for `groth16-ref verify` (`bend2/scripts/prove.sh` does this).
