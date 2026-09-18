//! Frozen JSON encoding: field elements as `0x`-prefixed big-endian hex of the
//! canonical (non-Montgomery) integer; G1/G2 affine points; infinity = `{"inf":true}`.

use ark_bn254::{Fq, Fq2, Fr, G1Affine, G2Affine};
use ark_ec::{short_weierstrass::{Affine, SWCurveConfig}, AffineRepr};
use ark_ff::{BigInteger, PrimeField};
use num_bigint::BigUint;
use serde::{Deserialize, Serialize};
use std::fmt;

pub fn hex_of_biguint(b: &BigUint) -> String {
    format!("0x{:x}", b)
}

pub fn hex<F: PrimeField>(f: &F) -> String {
    hex_of_biguint(&BigUint::from_bytes_be(&f.into_bigint().to_bytes_be()))
}

pub fn biguint_of_hex(s: &str) -> Result<BigUint, Error> {
    let t = s.strip_prefix("0x").ok_or_else(|| Error(format!("missing 0x prefix: {s}")))?;
    BigUint::parse_bytes(t.as_bytes(), 16).ok_or_else(|| Error(format!("bad hex: {s}")))
}

pub fn field_of_hex<F: PrimeField>(s: &str) -> Result<F, Error> {
    let b = biguint_of_hex(s)?;
    if b >= F::MODULUS.into() {
        return Err(Error(format!("not canonical (>= modulus): {s}")));
    }
    Ok(F::from(b))
}

#[derive(Debug)]
pub struct Error(pub String);
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Error {}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(untagged)]
pub enum G1Json {
    Inf { inf: bool },
    Affine { x: String, y: String },
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(untagged)]
pub enum G2Json {
    Inf { inf: bool },
    Affine { x: [String; 2], y: [String; 2] },
}

impl From<&G1Affine> for G1Json {
    fn from(p: &G1Affine) -> Self {
        match p.xy() {
            None => G1Json::Inf { inf: true },
            Some((x, y)) => G1Json::Affine { x: hex(&x), y: hex(&y) },
        }
    }
}

impl From<&G2Affine> for G2Json {
    fn from(p: &G2Affine) -> Self {
        match p.xy() {
            None => G2Json::Inf { inf: true },
            Some((x, y)) => G2Json::Affine {
                x: [hex(&x.c0), hex(&x.c1)],
                y: [hex(&y.c0), hex(&y.c1)],
            },
        }
    }
}

fn check_point<P: SWCurveConfig>(p: Affine<P>, what: &str) -> Result<Affine<P>, Error> {
    // `new_unchecked` skips curve/subgroup checks; do them explicitly so a bogus
    // proof is rejected rather than trusted.
    if !p.is_on_curve() || !p.is_in_correct_subgroup_assuming_on_curve() {
        return Err(Error(format!("{what}: point not on curve / not in subgroup")));
    }
    Ok(p)
}

impl G1Json {
    pub fn to_affine(&self) -> Result<G1Affine, Error> {
        match self {
            G1Json::Inf { inf: true } => Ok(G1Affine::identity()),
            G1Json::Inf { inf: false } => Err(Error("inf:false is not a point".into())),
            G1Json::Affine { x, y } => check_point(
                G1Affine::new_unchecked(field_of_hex::<Fq>(x)?, field_of_hex::<Fq>(y)?),
                "G1",
            ),
        }
    }
}

impl G2Json {
    pub fn to_affine(&self) -> Result<G2Affine, Error> {
        match self {
            G2Json::Inf { inf: true } => Ok(G2Affine::identity()),
            G2Json::Inf { inf: false } => Err(Error("inf:false is not a point".into())),
            G2Json::Affine { x, y } => {
                let fq2 = |c: &[String; 2]| -> Result<Fq2, Error> {
                    Ok(Fq2::new(field_of_hex::<Fq>(&c[0])?, field_of_hex::<Fq>(&c[1])?))
                };
                check_point(G2Affine::new_unchecked(fq2(x)?, fq2(y)?), "G2")
            }
        }
    }
}

pub fn g1s(ps: &[G1Affine]) -> Vec<G1Json> {
    ps.iter().map(G1Json::from).collect()
}
pub fn g2s(ps: &[G2Affine]) -> Vec<G2Json> {
    ps.iter().map(G2Json::from).collect()
}
pub fn frs(fs: &[Fr]) -> Vec<String> {
    fs.iter().map(hex).collect()
}

#[derive(Serialize, Deserialize)]
pub struct ProofJson {
    pub a: G1Json,
    pub b: G2Json,
    pub c: G1Json,
}

#[derive(Serialize, Deserialize)]
pub struct VkJson {
    pub alpha_g1: G1Json,
    pub beta_g2: G2Json,
    pub gamma_g2: G2Json,
    pub delta_g2: G2Json,
    pub gamma_abc_g1: Vec<G1Json>,
}

#[derive(Serialize, Deserialize)]
pub struct PublicJson {
    pub inputs: Vec<String>,
}

pub fn write_json<T: Serialize>(path: &std::path::Path, v: &T) -> std::io::Result<()> {
    let f = std::fs::File::create(path)?;
    let mut w = std::io::BufWriter::with_capacity(1 << 20, f);
    serde_json::to_writer(&mut w, v)?;
    std::io::Write::write_all(&mut w, b"\n")?;
    std::io::Write::flush(&mut w)
}

pub fn read_json<T: for<'de> Deserialize<'de>>(path: &std::path::Path) -> anyhow_lite::Result<T> {
    let f = std::fs::File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(serde_json::from_reader(std::io::BufReader::new(f))
        .map_err(|e| format!("{}: {e}", path.display()))?)
}

/// Minimal error alias so we don't pull in `anyhow`.
pub mod anyhow_lite {
    pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
}
