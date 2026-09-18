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
