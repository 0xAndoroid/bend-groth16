# Formal verification feasibility — Bend 2 Groth16 prover

**Checked 2026-09-18 against Bend 2.0.5** (`~/.bend/bin/bend --version`; checker `bend2/bend.ts`, base library
`bend2/base.bend`; upstream `bendlang/bend` @ `01e13b7`, 2026-09-18). Prototype: `bend2/proofs/`.

## Verdict: partially verifiable now

- **Yes:** Bend 2 is a real dependently-typed proof checker, and it checks theorems about *this repo's actual code*.
  `bend2/proofs/` contains 3 files that all print `All terms check.`: concrete theorems that run the generated 16-limb
  `Fr.add`/`Fr.sub`/`Fr.neg`/`Fr.mul` inside the checker (e.g. `Fr.mul(one, one) == one`, `Fr.add(one, -one) == zero`,
  2.7 s for the file), a **universal** commutativity theorem for a 2-limb carry-propagating add in the style of the
  generated code, and a **universal** U32 lemma (`x & 0 == 0` for all `x`) proven by induction on the bit vector.
- **Not yet:** nothing universal is proven about the real 16-limb field code, and no layer above it has a spec in Bend.
  The proof language has **no tactics/automation**, **no integer-semantics library for machine words** (Base ships one
  arithmetic lemma, `Word.add_comm`), **no algebra library** (rings/fields/polynomials), and **no export** to Lean/Rocq.
- **Trusted base is large and self-declared unaudited** (upstream README §Limitations: "the compiler (not kernel) is 99%
  AI-written and has not been fully audited", "the Lean formalization and bend.ts mismatch. Early consistency bugs may
  occur"). A Bend proof is a statement about the checker's term model, not about the C/Metal binary `comp.ts` emits.
- Honest framing for a publication: *"the field layer is provable in-language today at moderate cost; group, NTT/MSM
  and prover-equivalence proofs are months of work and would still rest on an unaudited checker and compiler"*.

## What Bend 2.0.5 actually supports (measured)

| Feature | Status in 2.0.5 | Evidence |
|---|---|---|
| Theorems | `law` = claim (a type), proven by a `def` of the same name; `bend file.bend` is the gate (`All terms check.`, else a typed error showing expected/observed terms). No separate `check` subcommand. | `guide/GUIDE.md` §Laws and Proofs; `main.ts:34-44`, `cli_report` |
| Equality | `{a == b : T}` intensional; `{==}` reflexivity after normalization; `%e : P` is the J-rewrite (motive `P` written by hand with `_` at the rewritten spot); `Equal.cong/sym/trans` in Base; `{a != b : T}` = `→ Empty`. | `bend.ts:214`, `base.bend:357-395` |
| Induction | Structural: `match` refines the goal per case, a self-call is the IH. Termination mandatory (strict subterm, left-to-right columns), no mutual recursion; `@unsafe` opts out and voids the guarantees (exit code still 0 — `WONTFIX.txt` #776). | `GUIDE.md` §Recursion; `bend.ts:221-228` |
| Universes | One universe, `Type : Type`, no positivity check; consistency argued via a live/dead "wall" (paper `BendTT.pdf`, Lean model `bend2/bend.lean`, 21k lines, 0 `sorry`, `#print axioms` for CR/SR/progress/normalization/consistency) — but README says the Lean model lags `bend.ts`. | `GUIDE.md` §Under the Hood; README §Limitations |
| U32 | **Not opaque.** `type U32 is Data: U32{data: Word(32n)}`; `U32.add/sub/mul/and/or/xor/shr` are Bend recursion over the bit vector (`Word.adc` ripple-carry). Proven by induction (prototype `u32_and_zero.bend`); the checker evaluates them by normalization (`65536*65536 == 0` and `(65535+65535) & 65535 == 65534` check by `{==}`). | `base.bend:44-133, 1022-1300` |
| Nat | Unary in the theory, 64-bit at runtime; `U32.to_nat` exists → integer specs are statable. | `base.bend:1358` |
| F32 | `law` with native implementation only — axiomatized, nothing provable. | `base.bend:1449-1606` |
| Arrays | `Array<T>` is an ordinary ADT (`ALeaf/ANode`) in the checker, single-owner at runtime; propositions may mention them and concrete `get/new` normalize (measured). Universal array lemmas = induction on the tree. | `base.bend:2122-2235`; scratch probe |
| Parallel `!` | A `!f(x)` call is an ordinary application to the checker; proofs cover it. Scheduler correctness is trusted. | `GUIDE.md` §Parallelism |
| Tactics, automation, decision procedures, SMT | None. Every rewrite motive is spelled out; a rewrite motive for the real `Fr.add` restates its ~115-line body. | `GUIDE.md`: "Bend has no tactics" |
| Export / independent kernel | None (no Lean/Agda/Rocq exporter; Kind/Kind2 lineage not carried over as tooling). | search, upstream repo |
| HVM / interaction nets | **Irrelevant to Bend 2**: runtime is BendRT (flat C state machine, fork-join), not HVM. No mechanized proofs of interaction-combinator or HVM correctness exist either way. | `GUIDE.md` §Under the Hood; bend2.dev notes |

## Prototype (`bend2/proofs/`, checked into this PR)

```sh
sh bend2/proofs/check.sh          # also wired into bend2/tests/run.sh ("proofs: OK")
# fr_concrete.bend: All terms check.      (2.7 s; runs Fr.add/sub/neg/mul/eq/is_zero on constants)
# limb_add_comm.bend: All terms check.    (∀ a b. add2(a,b) == add2(b,a), 2 rewrites with U32.add_comm)
# u32_and_zero.bend: All terms check.     (∀ x:U32. x & 0 == 0, induction on Word(n))
```

Sanity: a deliberately false theorem (`Fr.add(one, one) == one`) is rejected with the two normalized `Fr{…}` limb
vectors as expected/observed. The universal 2-limb proof shows the cost model: each `U32.add(a_i, b_i)` needs one
rewrite whose motive restates the whole goal, so the 16-limb `Fr.add_comm` is 16 motives × ~115 lines — mechanical, and
`bend2/gen/gen_field.py` should emit it rather than a human.

## Verifiable today vs. the path

| Layer | Spec | Today | Path (engineer-weeks, one person fluent in Bend proofs) |
|---|---|---|---|
| Word/U32 semantics | `U32.to_nat(add a b) == (to_nat a + to_nat b) mod 2^32`, same for `and/shr/mul`, carry lemmas | only `Word.add_comm` in Base; concrete instances by normalization | **3–5 wk**: a Bend `Word` library (to_nat of adc/shr/and/mul, bounds). Prerequisite for everything below. |
| Field Fr, Fq (16×16-bit limbs, Montgomery) | `to_int(add(a,b)) == (to_int a + to_int b) mod p`, `mul` = Montgomery product, `inv` | concrete theorems only (`fr_concrete.bend`) | **6–10 wk** per field family (Fr, Fq, Fq2): generated proof scripts from `gen_field.py`; fiat-crypto does this with heavy automation in Rocq, Bend has none. Ranges from fiat-crypto: 2–6 wk per prime *with* their pipeline. |
| Group G1/G2 | Jacobian `add/double` equal the affine group law; `msm` inputs on-curve | none | **8–16 wk** to show the formulas match the affine rational functions; a from-scratch associativity proof (Bartzia–Strub ≈10k lines Coq; Isabelle AFP entry) is **3–6 months** in a language with no algebra library. |
| NTT | `ntt(f)[i] == eval(f, ω^i)` over Fr, inverse round-trip | none; differential test vs arkworks | **4–8 wk** given field lemmas; needs `ω` primitive-root facts (Fr primality cannot be checked by normalization of a 254-bit prime — must be a certificate or an axiom). |
| MSM (Pippenger) | `msm(P, s) == Σ s_i·P_i` | none | **4–8 wk** given group law; no published verified Pippenger exists (gap in the literature). |
| Prover ≡ reference | Bend output equals a mathematical Groth16 prover on (pk, witness) | differential test only (`sh bend2/tests/run.sh`, K=4 prove vs arkworks) | **4–6 wk** wiring once layers exist. Equality to *arkworks* is not provable in any tool (Rust, no shared spec); the test stays as the bridge. |
| Checker/compiler trust | `bend.ts` ≡ `bend.lean`; `comp.ts` C/Metal emission preserves semantics | README: mismatch, unaudited | out of scope for this repo; the ceiling on what any Bend proof means. |

Total for an in-language end-to-end proof: **~30–55 engineer-weeks**, dominated by the missing libraries, and the
result is "correct relative to Bend 2.0.5's checker and compiler". A cheaper credible alternative is to port the
*algorithms* (not the Bend code) to Lean 4/Mathlib and prove them there — that verifies a model, not this binary.

## Sources

- Bend 2.0.5 install: `~/.bend/current/bend2/{bend.ts,base.bend,main.ts}`, `guide/GUIDE.md`; upstream https://github.com/bendlang/bend (README §Limitations, `WONTFIX.txt`, `bend2/bend.lean`, `paper/BendTT.pdf`, `paper/BendRT.pdf`, `demos/proof_numerics/`).
- Bend 2 notes: https://bend2.dev/notes/what-is-bend2/ , https://bend2.dev/notes/bend2-vs-lean/ (2026).
- Lafont, *Interaction Combinators*, Inf. & Comp. 1997, https://www.sciencedirect.com/science/article/pii/S0890540197926432 ; Mazza 2007 (symmetric IC); HVM2 paper (Taelin 2024, "work in progress") https://raw.githubusercontent.com/HigherOrderCO/HVM/main/paper/HVM2.pdf ; affinity caveat https://github.com/HigherOrderCO/HVM2/discussions/97 , https://github.com/HigherOrderCO/HVM1/issues/306 . No Rocq/Lean/Agda mechanization of IC or HVM found.
- Kind lineage: https://github.com/HigherOrderCO/kind2-archive ; Fu & Stump self types https://cse.sc.edu/~pfu/document/papers/rta-tlca.pdf . No Bend→Lean/Rocq exporter found.
- fiat-crypto https://github.com/mit-plv/fiat-crypto ; Erbsen et al., S&P 2019 https://www.wireguard.com/papers/erbsen-philipoom-gross-sloan-chlipala-fiat-2019.pdf .
- EC group law: Bartzia & Strub, ITP 2014 https://link.springer.com/chapter/10.1007/978-3-319-08970-6_6 ; Isabelle AFP *Elliptic_Curves_Group_Law* (2017); elementary proof ITP 2023 https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ITP.2023.6 .
- NTT: *Formally Verifying Kyber* (Almeida et al., TCHES/Crypto 2024) https://eprint.iacr.org/2024/843 ; Plantard NTT follow-up https://eprint.iacr.org/2026/1624.pdf .
- ZK tooling (circuits, not provers): Picus https://github.com/Veridise/Picus ; Coda https://arxiv.org/abs/2304.07648 ; gnark-lean-extractor https://github.com/reilabs/gnark-lean-extractor ; Clean https://github.com/Verified-zkEVM/clean/ ; Bailey & Miller, *Formalizing Soundness Proofs of Linear PCP SNARKs* (Groth16 in Lean, AGM), USENIX Sec 2024 https://www.usenix.org/system/files/usenixsecurity24-bailey.pdf ; SNARKProbe (differential testing vs arkworks) https://link.springer.com/chapter/10.1007/978-3-031-54773-7_14 .
