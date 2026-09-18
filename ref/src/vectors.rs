//! `vectors`: primitive test vectors (field, G1/G2, MSM, NTT) for the Bend implementation.

use crate::circuit;
use crate::json::{self, anyhow_lite::Result, hex, hex_of_biguint, G1Json, G2Json};
use ark_bn254::{Fq, Fr, G1Affine, G1Projective, G2Affine, G2Projective};
use ark_ec::{AffineRepr, CurveGroup, VariableBaseMSM};
use ark_ff::{BigInteger, PrimeField, UniformRand};
use ark_poly::{EvaluationDomain, Radix2EvaluationDomain};
use ark_std::rand::Rng;
use num_bigint::BigUint;
use serde::Serialize;
use std::path::Path;

#[derive(Serialize)]
struct FieldConsts {
    p: String,
    r_mod_p: String,
    r2_mod_p: String,
    n_prime_12: String,
    n_prime_24: String,
    n_prime_32: String,
    n_prime_64: String,
}

#[derive(Serialize)]
struct FieldCase {
    a: String,
    b: String,
    add: String,
    sub: String,
    mul: String,
    neg_a: String,
    inv_a: String,
    sq_a: String,
    a_mont: String,
    mul_mont: String,
}

#[derive(Serialize)]
struct FieldVectors {
    constants: FieldConsts,
    cases: Vec<FieldCase>,
}

fn modulus<F: PrimeField>() -> BigUint {
    BigUint::from_bytes_be(&F::MODULUS.to_bytes_be())
}

/// -p^{-1} mod 2^bits (bits <= 64), via Newton iteration on the low 64 bits of p.
fn n_prime(p: &BigUint, bits: u32) -> String {
    let p64 = p.iter_u64_digits().next().unwrap();
    let mut inv: u64 = 1;
    for _ in 0..7 {
        inv = inv.wrapping_mul(2u64.wrapping_sub(p64.wrapping_mul(inv)));
    }
    debug_assert_eq!(p64.wrapping_mul(inv), 1);
    let mask = if bits == 64 { u64::MAX } else { (1u64 << bits) - 1 };
    let n = inv.wrapping_neg() & mask;
    format!("0x{:x}", n)
}

fn to_mont<F: PrimeField>(a: &F, p: &BigUint) -> String {
    let r = BigUint::from(1u8) << 256;
    let ab = BigUint::from_bytes_be(&a.into_bigint().to_bytes_be());
    hex_of_biguint(&((ab * r) % p))
}

fn field_vectors<F: PrimeField, R: Rng>(rng: &mut R, n: usize) -> FieldVectors {
    let p = modulus::<F>();
    let r = BigUint::from(1u8) << 256;
    let r_mod_p = &r % &p;
    let r2_mod_p = (&r * &r) % &p;
    let cases = (0..n)
        .map(|_| {
            let a = F::rand(rng);
            let b = F::rand(rng);
            let mul = a * b;
            FieldCase {
                a: hex(&a),
                b: hex(&b),
                add: hex(&(a + b)),
                sub: hex(&(a - b)),
                mul: hex(&mul),
                neg_a: hex(&(-a)),
                inv_a: hex(&ark_ff::Field::inverse(&a).unwrap_or(F::ZERO)),
                sq_a: hex(&a.square()),
                a_mont: to_mont(&a, &p),
                mul_mont: to_mont(&mul, &p),
            }
        })
        .collect();
    FieldVectors {
        constants: FieldConsts {
            p: hex_of_biguint(&p),
            r_mod_p: hex_of_biguint(&r_mod_p),
            r2_mod_p: hex_of_biguint(&r2_mod_p),
            n_prime_12: n_prime(&p, 12),
            n_prime_24: n_prime(&p, 24),
            n_prime_32: n_prime(&p, 32),
            n_prime_64: n_prime(&p, 64),
        },
        cases,
    }
}

#[derive(Serialize)]
struct CurveCase<P> {
    p: P,
    q: P,
    k: String,
    add: P,
    double_p: P,
    neg_p: P,
    mul_pk: P,
}

fn curve_vectors<G, J, R>(rng: &mut R, n: usize) -> Vec<CurveCase<J>>
where
    G: CurveGroup + UniformRand,
    for<'a> J: From<&'a G::Affine>,
    R: Rng,
{
    let j = |g: G| J::from(&g.into_affine());
    (0..n)
        .map(|i| {
            let mut p = G::rand(rng);
            let mut q = G::rand(rng);
            match i {
                0 => p = G::zero(),           // infinity case
                1 => q = p,                   // p == q
                2 => q = -p,                  // p + q = infinity
                _ => {}
            }
            let k = G::ScalarField::rand(rng);
            CurveCase {
                p: j(p),
                q: j(q),
                k: hex(&k),
                add: j(p + q),
                double_p: j(p.double()),
                neg_p: j(-p),
                mul_pk: j(p * k),
            }
        })
        .collect()
}

#[derive(Serialize)]
struct MsmCase {
    size: usize,
    points: Vec<G1Json>,
    scalars: Vec<String>,
    result: G1Json,
}

#[derive(Serialize)]
struct NttCase {
    size: usize,
    omega: String,
    domain_size_inv: String,
    coeffs: Vec<String>,
    evals: Vec<String>,
    icoeffs_of_evals: Vec<String>,
}

pub fn run(out: &Path) -> Result<()> {
    std::fs::create_dir_all(out)?;
    let mut rng = circuit::rng();

    json::write_json(&out.join("fr_ops.json"), &field_vectors::<Fr, _>(&mut rng, 64))?;
    json::write_json(&out.join("fq_ops.json"), &field_vectors::<Fq, _>(&mut rng, 64))?;
    json::write_json(&out.join("g1_ops.json"), &curve_vectors::<G1Projective, G1Json, _>(&mut rng, 32))?;
    json::write_json(&out.join("g2_ops.json"), &curve_vectors::<G2Projective, G2Json, _>(&mut rng, 16))?;

    let msm: Vec<MsmCase> = [8usize, 64, 1024]
        .iter()
        .map(|&size| {
            let pts: Vec<G1Affine> = (0..size).map(|_| G1Affine::rand(&mut rng)).collect();
            let sc: Vec<Fr> = (0..size).map(|_| Fr::rand(&mut rng)).collect();
            let res = G1Projective::msm(&pts, &sc).unwrap().into_affine();
            MsmCase { size, points: json::g1s(&pts), scalars: json::frs(&sc), result: (&res).into() }
        })
        .collect();
    json::write_json(&out.join("msm_small.json"), &msm)?;

    let ntt: Vec<NttCase> = [8usize, 64, 1024]
        .iter()
        .map(|&size| {
            let d = Radix2EvaluationDomain::<Fr>::new(size).unwrap();
            let coeffs: Vec<Fr> = (0..size).map(|_| Fr::rand(&mut rng)).collect();
            let evals = d.fft(&coeffs);
            let icoeffs = d.ifft(&evals);
            assert_eq!(icoeffs, coeffs);
            NttCase {
                size,
                omega: hex(&d.group_gen),
                domain_size_inv: hex(&d.size_inv),
                coeffs: json::frs(&coeffs),
                evals: json::frs(&evals),
                icoeffs_of_evals: json::frs(&icoeffs),
            }
        })
        .collect();
    json::write_json(&out.join("ntt_small.json"), &ntt)?;

    // sanity: G2 generator round-trips through the JSON encoding
    let g2 = G2Affine::generator();
    assert_eq!(G2Json::from(&g2).to_affine()?, g2);
    let _ = G1Affine::generator();
    println!("vectors written to {}", out.display());
    Ok(())
}
