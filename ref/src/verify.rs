//! `verify`: check an externally produced proof (frozen JSON encoding) against vk + public inputs.

use crate::json::{self, anyhow_lite::Result, ProofJson, PublicJson, VkJson};
use ark_bn254::{Bn254, Fr};
use ark_groth16::{Groth16, Proof, VerifyingKey};
use std::path::Path;

pub fn run(vk: &Path, proof: &Path, public: &Path) -> Result<bool> {
    let vk: VkJson = json::read_json(vk)?;
    let proof: ProofJson = json::read_json(proof)?;
    let public: PublicJson = json::read_json(public)?;
    let vk = VerifyingKey::<Bn254> {
        alpha_g1: vk.alpha_g1.to_affine()?,
        beta_g2: vk.beta_g2.to_affine()?,
        gamma_g2: vk.gamma_g2.to_affine()?,
        delta_g2: vk.delta_g2.to_affine()?,
        gamma_abc_g1: vk.gamma_abc_g1.iter().map(|p| p.to_affine()).collect::<std::result::Result<_, _>>()?,
    };
    let proof = Proof::<Bn254> {
        a: proof.a.to_affine()?,
        b: proof.b.to_affine()?,
        c: proof.c.to_affine()?,
    };
    let inputs: Vec<Fr> = public.inputs.iter().map(|s| json::field_of_hex(s)).collect::<std::result::Result<_, _>>()?;
    let pvk = ark_groth16::prepare_verifying_key(&vk);
    Ok(Groth16::<Bn254>::verify_proof(&pvk, &proof, &inputs)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::G1Json;

    #[test]
    fn accepts_reference_proof_and_rejects_tampering() {
        let dir = std::env::temp_dir().join(format!("groth16-ref-test-{}", std::process::id()));
        crate::gen::run(2, &dir).unwrap();
        let (vk, proof, public) = (dir.join("vk.json"), dir.join("proof_ref.json"), dir.join("public.json"));
        assert!(run(&vk, &proof, &public).unwrap());
        let bad_pub = dir.join("bad_public.json");
        std::fs::write(&bad_pub, r#"{"inputs":["0x2"]}"#).unwrap();
        assert!(!run(&vk, &proof, &bad_pub).unwrap());
        let p: ProofJson = json::read_json(&proof).unwrap();
        let bad_c = dir.join("bad_c.json"); // valid point, wrong proof
        json::write_json(&bad_c, &ProofJson { a: p.a.clone(), b: p.b.clone(), c: G1Json::Inf { inf: true } }).unwrap();
        assert!(!run(&vk, &bad_c, &public).unwrap());
        let bad_a = dir.join("bad_a.json"); // off-curve point → error, not trusted
        json::write_json(&bad_a, &ProofJson { a: G1Json::Affine { x: "0x1".into(), y: "0x1".into() }, b: p.b, c: p.c }).unwrap();
        assert!(run(&vk, &bad_a, &public).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
