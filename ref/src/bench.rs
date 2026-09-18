//! `bench`: arkworks CPU data point (rayon, all threads) → bench/arkworks-<host>.json.

use crate::circuit::{self, SquareChain};
use crate::json::anyhow_lite::Result;
use ark_bn254::{Bn254, Fr, G1Affine, G1Projective, G2Affine, G2Projective};
use ark_ec::{CurveGroup, VariableBaseMSM};
use ark_ff::UniformRand;
use ark_groth16::Groth16;
use ark_poly::{EvaluationDomain, Radix2EvaluationDomain};
use serde_json::{json, Map, Value};
use std::hint::black_box;
use std::path::Path;
use std::time::Instant;

/// One untimed warm-up call, then `iters` timed calls → (median, samples).
fn median_ms<F: FnMut()>(iters: usize, mut f: F) -> (f64, Vec<f64>) {
    f();
    let mut v: Vec<f64> = (0..iters)
        .map(|_| {
            let t = Instant::now();
            f();
            t.elapsed().as_secs_f64() * 1e3
        })
        .collect();
    let samples = v.clone();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (v[v.len() / 2], samples)
}

fn host() -> String {
    let h = std::process::Command::new("hostname").arg("-s").output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_else(|| "unknown".into());
    let h: String = h.trim().to_lowercase().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    if h.is_empty() { "unknown".into() } else { h }
}

fn cmd(c: &str, args: &[&str]) -> Option<String> {
    std::process::Command::new(c).args(args).output().ok()
        .and_then(|o| String::from_utf8(o.stdout).ok()).map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

/// 1/5/15-min load averages at measurement time (sibling jobs inflate every number below).
fn loadavg() -> Option<String> {
    cmd("sysctl", &["-n", "vm.loadavg"]).or_else(|| cmd("cat", &["/proc/loadavg"]))
}

fn load(path: &Path) -> Map<String, Value> {
    std::fs::read(path).ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default()
}

fn save(path: &Path, mut doc: Map<String, Value>) -> Result<()> {
    doc.insert("schema".into(), json!(1));
    doc.insert("framework".into(), json!("arkworks"));
    doc.insert("versions".into(), json!({"ark-groth16": "0.5.0", "ark-bn254": "0.5.0"}));
    doc.insert("host".into(), json!(host()));
    doc.insert("cpu".into(), json!(cmd("sysctl", &["-n", "machdep.cpu.brand_string"]).or_else(|| cmd("uname", &["-m"]))));
    doc.insert("threads".into(), json!(rayon::current_num_threads()));
    doc.insert("git_head".into(), json!(cmd("git", &["rev-parse", "--short", "HEAD"])));
    doc.insert("updated".into(), json!(chrono::Utc::now().to_rfc3339()));
    std::fs::create_dir_all(path.parent().unwrap())?;
    std::fs::write(path, serde_json::to_string_pretty(&Value::Object(doc))? + "\n")?;
    println!("wrote {}", path.display());
    Ok(())
}

fn out_path(dir: &Path) -> std::path::PathBuf {
    dir.join(format!("arkworks-{}.json", host()))
}

fn section<'a>(doc: &'a mut Map<String, Value>, key: &str) -> &'a mut Map<String, Value> {
    doc.entry(key).or_insert_with(|| json!({})).as_object_mut().unwrap()
}

pub fn prove(log2: u32, iters: usize, out_dir: &Path) -> Result<()> {
    let n = 1usize << log2;
    let circuit = SquareChain::random(n);
    let mut rng = circuit::rng();
    // Same seed as `gen`, so this is the very pk exported to data/K/ (regenerating is faster
    // than deserializing pk.bin: 2 s vs 12 s at 2^18).
    let t = Instant::now();
    let pk = Groth16::<Bn254>::generate_random_parameters_with_reduction(circuit.clone(), &mut rng)?;
    eprintln!("setup 2^{log2}: {:.1}s", t.elapsed().as_secs_f64());
    let proof = Groth16::<Bn254>::create_random_proof_with_reduction(circuit.clone(), &pk, &mut rng)?;
    let pvk = ark_groth16::prepare_verifying_key(&pk.vk);
    assert!(Groth16::<Bn254>::verify_proof(&pvk, &proof, &[circuit.public()])?);
    let (ms, samples) = median_ms(iters, || {
        black_box(Groth16::<Bn254>::create_random_proof_with_reduction(circuit.clone(), &pk, &mut rng).unwrap());
    });
    // Prover-only path: matrices + full assignment precomputed (what a Bend prover fed r1cs.json/witness.json does).
    let (m, z) = crate::gen::matrices_and_assignment(&circuit);
    let (r, s) = (Fr::rand(&mut rng), Fr::rand(&mut rng));
    let (matrices_ms, matrices_samples) = median_ms(iters, || {
        black_box(Groth16::<Bn254>::create_proof_with_reduction_and_matrices(&pk, r, s, &m, 2, n, &z).unwrap());
    });
    println!("prove 2^{log2} (N={n}): full {ms:.1} ms, matrices-only {matrices_ms:.1} ms (median of {iters}, {} threads)", rayon::current_num_threads());
    let path = out_path(out_dir);
    let mut doc = load(&path);
    section(&mut doc, "prove").insert(log2.to_string(), json!({
        "log2": log2, "num_constraints": n, "ms": ms, "iters": iters, "samples_ms": samples,
        "prove_matrices_ms": matrices_ms, "prove_matrices_samples_ms": matrices_samples,
        "timestamp": chrono::Utc::now().to_rfc3339(), "loadavg": loadavg(),
    }));
    save(&path, doc)
}

pub fn primitives(it: usize, out_dir: &Path, max_log2: u32) -> Result<()> {
    let path = out_path(out_dir);
    let mut doc = load(&path);
    let mut rng = circuit::rng();
    let stamp = || chrono::Utc::now().to_rfc3339();

    // MSM G1 2^10..2^max, G2 2^10..2^16 — random affine points, random scalars, fresh per size.
    let top = max_log2.min(20);
    let pts: Vec<G1Affine> = G1Projective::normalize_batch(&(0..1usize << top).map(|_| G1Projective::rand(&mut rng)).collect::<Vec<_>>());
    let sc: Vec<Fr> = (0..1usize << top).map(|_| Fr::rand(&mut rng)).collect();
    for k in 10..=top {
        let n = 1usize << k;
        let (ms, samples) = median_ms(it, || { let _ = black_box(G1Projective::msm(&pts[..n], &sc[..n]).unwrap()); });
        println!("msm_g1 2^{k}: {ms:.2} ms");
        section(&mut doc, "msm_g1").insert(k.to_string(), json!({"log2": k, "ms": ms, "iters": it, "samples_ms": samples, "timestamp": stamp(), "loadavg": loadavg()}));
    }
    drop(pts);
    let top2 = max_log2.min(16);
    let pts2: Vec<G2Affine> = G2Projective::normalize_batch(&(0..1usize << top2).map(|_| G2Projective::rand(&mut rng)).collect::<Vec<_>>());
    for k in 10..=top2 {
        let n = 1usize << k;
        let (ms, samples) = median_ms(it, || { let _ = black_box(G2Projective::msm(&pts2[..n], &sc[..n]).unwrap()); });
        println!("msm_g2 2^{k}: {ms:.2} ms");
        section(&mut doc, "msm_g2").insert(k.to_string(), json!({"log2": k, "ms": ms, "iters": it, "samples_ms": samples, "timestamp": stamp(), "loadavg": loadavg()}));
    }
    drop(pts2);

    // NTT / iNTT over Fr.
    for k in 10..=top {
        let n = 1usize << k;
        let d = Radix2EvaluationDomain::<Fr>::new(n).unwrap();
        let coeffs = &sc[..n];
        let (fft_ms, fft_samples) = median_ms(it, || { black_box(d.fft(coeffs)); });
        let (ifft_ms, ifft_samples) = median_ms(it, || { black_box(d.ifft(coeffs)); });
        println!("ntt 2^{k}: fft {fft_ms:.2} ms, ifft {ifft_ms:.2} ms");
        section(&mut doc, "ntt").insert(k.to_string(), json!({"log2": k, "fft_ms": fft_ms, "ifft_ms": ifft_ms, "iters": it,
            "fft_samples_ms": fft_samples, "ifft_samples_ms": ifft_samples, "timestamp": stamp(), "loadavg": loadavg()}));
    }

    // Fr mul throughput, single thread.
    const N_MULS: usize = 10_000_000;
    let mut x = Fr::rand(&mut rng);
    let y = Fr::rand(&mut rng);
    let t = Instant::now();
    for _ in 0..N_MULS { x *= black_box(y); }
    black_box(x);
    let dep = N_MULS as f64 / t.elapsed().as_secs_f64();
    let a: Vec<Fr> = sc[..1 << 20].to_vec();
    let b: Vec<Fr> = a.iter().rev().cloned().collect();
    let mut out = vec![Fr::from(0u64); a.len()];
    let rounds = N_MULS / a.len();
    let t = Instant::now();
    for _ in 0..rounds {
        for i in 0..a.len() { out[i] = a[i] * b[i]; }
        black_box(&out);
    }
    let indep = (rounds * a.len()) as f64 / t.elapsed().as_secs_f64();
    println!("fr_mul: dependent {:.1} M/s, independent {:.1} M/s (single thread)", dep / 1e6, indep / 1e6);
    doc.insert("fr_mul".into(), json!({"dependent_muls_per_sec": dep, "independent_muls_per_sec": indep,
        "n_muls": N_MULS, "batch": a.len(), "threads": 1, "timestamp": stamp(), "loadavg": loadavg()}));
    save(&path, doc)
}
