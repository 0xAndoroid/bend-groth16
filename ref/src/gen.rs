//! `gen`: setup + witness + reference proof for SquareChain(2^K), exported as frozen JSON.

use crate::circuit::{self, SquareChain};
use crate::json::{self, anyhow_lite::Result, G1Json, G2Json, ProofJson, PublicJson, VkJson};
use ark_bn254::{Bn254, Fr};
use ark_ff::UniformRand;
use ark_groth16::{Groth16, ProvingKey};
use ark_poly::{EvaluationDomain, GeneralEvaluationDomain};
use ark_relations::r1cs::{
    ConstraintMatrices, ConstraintSynthesizer, ConstraintSystem, OptimizationGoal, SynthesisMode,
};
use serde::Serialize;
use std::path::Path;
use std::time::Instant;

#[derive(Serialize)]
struct R1csJson {
    num_constraints: usize,
    num_instance: usize,
    num_witness: usize,
    a: Vec<Vec<(usize, String)>>,
    b: Vec<Vec<(usize, String)>>,
    c: Vec<Vec<(usize, String)>>,
}

#[derive(Serialize)]
struct WitnessJson {
    z: Vec<String>,
}

#[derive(Serialize)]
struct PkJson {
    domain_size: usize,
    alpha_g1: G1Json,
    beta_g1: G1Json,
    beta_g2: G2Json,
    delta_g1: G1Json,
    delta_g2: G2Json,
    a_query: Vec<G1Json>,
    b_g1_query: Vec<G1Json>,
    b_g2_query: Vec<G2Json>,
    h_query: Vec<G1Json>,
    l_query: Vec<G1Json>,
    vk: VkJson,
}

#[derive(Serialize)]
struct RsJson {
    r: String,
    s: String,
}

pub fn vk_json(vk: &ark_groth16::VerifyingKey<Bn254>) -> VkJson {
    VkJson {
        alpha_g1: (&vk.alpha_g1).into(),
        beta_g2: (&vk.beta_g2).into(),
        gamma_g2: (&vk.gamma_g2).into(),
        delta_g2: (&vk.delta_g2).into(),
        gamma_abc_g1: json::g1s(&vk.gamma_abc_g1),
    }
}

/// Synthesize the circuit in prove mode and return (matrices, full assignment).
/// Mirrors `Groth16::create_random_proof_with_reduction`.
pub fn matrices_and_assignment(circuit: &SquareChain) -> (ConstraintMatrices<Fr>, Vec<Fr>) {
    let cs = ConstraintSystem::<Fr>::new_ref();
    cs.set_optimization_goal(OptimizationGoal::Constraints);
    cs.set_mode(SynthesisMode::Prove { construct_matrices: true });
    circuit.clone().generate_constraints(cs.clone()).unwrap();
    cs.finalize();
    assert!(cs.is_satisfied().unwrap(), "circuit unsatisfied");
    let m = cs.to_matrices().unwrap();
    let z = [cs.borrow().unwrap().instance_assignment.clone(), cs.borrow().unwrap().witness_assignment.clone()].concat();
    // Frozen-shape checks: z = [1, x_N, x_0..x_{N-1}]; row i: A=B=[(2+i,1)], C=[(3+i,1)] or [(1,1)] last.
    let n = circuit.n;
    assert_eq!(z, circuit.assignment());
    assert_eq!((m.num_instance_variables, m.num_witness_variables, m.num_constraints), (2, n, n));
    for i in 0..n {
        let next = if i + 1 == n { 1 } else { 3 + i };
        assert_eq!(m.a[i], vec![(Fr::from(1u64), 2 + i)]);
        assert_eq!(m.b[i], vec![(Fr::from(1u64), 2 + i)]);
        assert_eq!(m.c[i], vec![(Fr::from(1u64), next)]);
    }
    (m, z)
}

fn rows(m: &[Vec<(Fr, usize)>]) -> Vec<Vec<(usize, String)>> {
    m.iter().map(|r| r.iter().map(|(c, i)| (*i, json::hex(c))).collect()).collect()
}

pub fn domain_size(n: usize) -> usize {
    GeneralEvaluationDomain::<Fr>::new(n + 2).unwrap().size()
}

pub fn run(log2: u32, out: &Path) -> Result<()> {
    let n = 1usize << log2;
    std::fs::create_dir_all(out)?;
    let t0 = Instant::now();
    let circuit = SquareChain::random(n);
    let mut rng = circuit::rng();

    let t = Instant::now();
    let pk: ProvingKey<Bn254> =
        Groth16::<Bn254>::generate_random_parameters_with_reduction(circuit.clone(), &mut rng)?;
    eprintln!("setup 2^{log2}: {:.1}s", t.elapsed().as_secs_f64());

    let (m, z) = matrices_and_assignment(&circuit);
    let r = Fr::rand(&mut rng);
    let s = Fr::rand(&mut rng);
    let t = Instant::now();
    let proof = Groth16::<Bn254>::create_proof_with_reduction_and_matrices(&pk, r, s, &m, 2, n, &z)?;
    eprintln!("prove (fixed r,s): {:.3}s", t.elapsed().as_secs_f64());
    let pvk = ark_groth16::prepare_verifying_key(&pk.vk);
    assert!(Groth16::<Bn254>::verify_proof(&pvk, &proof, &[circuit.public()])?, "reference proof failed to verify");

    let d = domain_size(n);
    assert_eq!(pk.h_query.len(), d - 1);
    assert_eq!(pk.a_query.len(), n + 2);
    assert_eq!(pk.l_query.len(), n);

    json::write_json(&out.join("r1cs.json"), &R1csJson {
        num_constraints: n,
        num_instance: 2,
        num_witness: n,
        a: rows(&m.a),
        b: rows(&m.b),
        c: rows(&m.c),
    })?;
    json::write_json(&out.join("witness.json"), &WitnessJson { z: json::frs(&z) })?;
    json::write_json(&out.join("public.json"), &PublicJson { inputs: vec![json::hex(&circuit.public())] })?;
    json::write_json(&out.join("vk.json"), &vk_json(&pk.vk))?;
    json::write_json(&out.join("proof_ref.json"), &ProofJson {
        a: (&proof.a).into(),
        b: (&proof.b).into(),
        c: (&proof.c).into(),
    })?;
    json::write_json(&out.join("proof_ref_rs.json"), &RsJson { r: json::hex(&r), s: json::hex(&s) })?;
    let t = Instant::now();
    json::write_json(&out.join("pk.json"), &PkJson {
        domain_size: d,
        alpha_g1: (&pk.vk.alpha_g1).into(),
        beta_g1: (&pk.beta_g1).into(),
        beta_g2: (&pk.vk.beta_g2).into(),
        delta_g1: (&pk.delta_g1).into(),
        delta_g2: (&pk.vk.delta_g2).into(),
        a_query: json::g1s(&pk.a_query),
        b_g1_query: json::g1s(&pk.b_g1_query),
        b_g2_query: json::g2s(&pk.b_g2_query),
        h_query: json::g1s(&pk.h_query),
        l_query: json::g1s(&pk.l_query),
        vk: vk_json(&pk.vk),
    })?;
    eprintln!("pk.json write: {:.1}s", t.elapsed().as_secs_f64());

    let mut total = 0u64;
    for e in std::fs::read_dir(out)? {
        let e = e?;
        let len = e.metadata()?.len();
        total += len;
        println!("{:>12}  {}", len, e.path().display());
    }
    println!("gen 2^{log2}: N={n} domain_size={d} total_bytes={total} wall={:.1}s", t0.elapsed().as_secs_f64());
    Ok(())
}
