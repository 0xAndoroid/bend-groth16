//! Canonical `SquareChain(N)` circuit (FROZEN across all frameworks).
//!
//! Private witness `x0`; `x_{i+1} = x_i * x_i` for `i in 0..N`; `x_N` is the single
//! public input. Exactly `N` R1CS constraints. Assignment vector
//! `z = [1, x_N, x_0, ..., x_{N-1}]` (arkworks ordering: instance first).

use ark_bn254::Fr;
use ark_ff::{Field, UniformRand};
use ark_relations::r1cs::{
    ConstraintSynthesizer, ConstraintSystemRef, LinearCombination, SynthesisError, Variable,
};
use ark_std::rand::{rngs::StdRng, SeedableRng};

pub const SEED: u64 = 42;

pub fn rng() -> StdRng {
    StdRng::seed_from_u64(SEED)
}

#[derive(Clone)]
pub struct SquareChain {
    pub n: usize,
    /// `x_0 .. x_N` (length `n + 1`).
    pub xs: Vec<Fr>,
}

impl SquareChain {
    pub fn new(n: usize, x0: Fr) -> Self {
        let mut xs = Vec::with_capacity(n + 1);
        xs.push(x0);
        for i in 0..n {
            xs.push(xs[i].square());
        }
        Self { n, xs }
    }

    pub fn random(n: usize) -> Self {
        // Fresh deterministic rng so the witness does not depend on setup randomness.
        let mut r = StdRng::seed_from_u64(SEED ^ 0x5157_4e45_5353); // "WTNESS"
        Self::new(n, Fr::rand(&mut r))
    }

    pub fn public(&self) -> Fr {
        self.xs[self.n]
    }

    /// Full assignment `z = [1, x_N, x_0..x_{N-1}]`.
    pub fn assignment(&self) -> Vec<Fr> {
        let mut z = Vec::with_capacity(self.n + 2);
        z.push(Fr::ONE);
        z.push(self.public());
        z.extend_from_slice(&self.xs[..self.n]);
        z
    }
}

impl ConstraintSynthesizer<Fr> for SquareChain {
    fn generate_constraints(self, cs: ConstraintSystemRef<Fr>) -> Result<(), SynthesisError> {
        let out = cs.new_input_variable(|| Ok(self.public()))?;
        let mut vars: Vec<Variable> = Vec::with_capacity(self.n);
        for i in 0..self.n {
            vars.push(cs.new_witness_variable(|| Ok(self.xs[i]))?);
        }
        for i in 0..self.n {
            let next = if i + 1 == self.n { out } else { vars[i + 1] };
            cs.enforce_constraint(
                LinearCombination::from(vars[i]),
                LinearCombination::from(vars[i]),
                LinearCombination::from(next),
            )?;
        }
        Ok(())
    }
}
