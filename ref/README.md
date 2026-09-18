# ref/ — arkworks Groth16/BN254 reference harness (`groth16-ref`)

```sh
cargo run --release -- gen --log2 K --out ../data/K/      # r1cs, witness, public, pk, vk, proof_ref(+_rs)
cargo run --release -- verify --vk vk.json --proof proof.json --public public.json   # OK=0 / INVALID=1
cargo run --release -- vectors --out ../data/vectors/     # fr/fq/g1/g2 ops, msm_small, ntt_small
cargo run --release -- bench --log2 K --primitives        # → ../bench/arkworks-<host>.json
```

Circuit: `SquareChain(N=2^K)` — private `x0`, `x_{i+1} = x_i²`, `x_N` public; `N` constraints,
`z = [1, x_N, x_0..x_{N-1}]`. All randomness is `StdRng::seed_from_u64(42)` (setup) and
`42 ^ 0x51574e455353` (witness), so `gen` and `bench` build the identical pk.

## Frozen JSON encoding
- Field element: `"0x…"` big-endian hex of the canonical integer (no Montgomery form, no padding).
- G1: `{"x","y"}`; G2: `{"x":[c0,c1],"y":[c0,c1]}`; infinity: `{"inf":true}`.
- `r1cs.json`: `a|b|c[row] = [[col, coeff], …]`, columns index `z` (instance first: 0 = 1, 1 = x_N,
  2.. = witness). `witness.json.z`, `public.json.inputs = [x_N]`.
- `pk.json`: `domain_size` (= smallest 2^k ≥ N+2), `alpha_g1, beta_g1, beta_g2, delta_g1, delta_g2`,
  `a_query[N+2], b_g1_query[N+2], b_g2_query[N+2], h_query[domain_size-1], l_query[N]`, `vk`.
- `vectors/*_ops.json.constants`: `p`, `r_mod_p = 2^256 mod p`, `r2_mod_p`, `n_prime_k = -p^{-1} mod 2^k`;
  each case carries `a_mont = a·2^256 mod p` next to the canonical value.

## Reproducing `proof_ref.json` bit-for-bit (ark-groth16 0.5, libsnark reduction)
With `r, s` from `proof_ref_rs.json`, `d = domain_size`, `z` the full assignment:
1. `A_i(x), B_i(x), C_i(x)` are the Lagrange interpolations over the size-`d` radix-2 domain of the
   R1CS columns, **plus** for instance variable `i ∈ {0,1}` an extra row `N+i` in `A` only
   (`a[N+i] = z[i]`, libsnark's input-consistency rows). `h(x) = (A·B − C)/Z_d`, computed on the coset
   `g·H` (`g = Fr::GENERATOR = 5`); its `d−1` coefficients pair with `h_query`.
2. `A  = α₁ + a_query[0] + Σ_{i≥1} z[i]·a_query[i] + r·δ₁`
3. `B₂ = β₂ + b_g2_query[0] + Σ_{i≥1} z[i]·b_g2_query[i] + s·δ₂` (and `B₁` likewise with `β₁, δ₁`)
4. `C  = s·A + r·B₁ − r·s·δ₁ + Σ_{j<N} z[2+j]·l_query[j] + Σ_{k<d−1} h[k]·h_query[k]`
Points are output in affine form; `verify` checks on-curve + subgroup before pairing.
