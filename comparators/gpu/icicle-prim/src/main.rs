//! ICICLE v4.0.0 BN254 primitive timings on one CUDA device: G1 MSM (2^10..2^20) and Fr NTT (2^10..2^20).
//! Every timed call is synchronous (`is_async=false`, blocking until the device finishes), so a sample is
//! wall time of one kernel launch sequence including any host<->device copy the variant implies:
//!   msm_device : scalars + bases already on device, result on device        (kernel-only + launch)
//!   msm_host   : scalars on host (H2D each call), bases cached on device    (== gnark/icicle-gnark usage)
//!   ntt_device : in-place on a device buffer                                 (kernel-only + launch)
//!   ntt_host   : host input, host output (H2D + D2H)
//! Usage: icicle-prim [--min 10] [--max 20] [--iters 10] > json
use icicle_bn254::curve::{G1Affine, G1Projective, ScalarField};
use icicle_core::msm::{msm, precompute_bases, MSMConfig};
use icicle_core::ntt::{get_root_of_unity, initialize_domain, ntt, ntt_inplace, NTTConfig, NTTDir, NTTInitDomainConfig};
use icicle_core::projective::Projective;
use icicle_core::bignum::BigNum;
use icicle_core::traits::GenerateRandom;
use icicle_runtime::memory::{DeviceVec, HostSlice};
use icicle_runtime::{device::Device, runtime::load_backend_from_env_or_default, set_device};
use serde_json::{json, Value};
use std::time::Instant;

fn median(v: &mut Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = v.len();
    if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 }
}

fn timed<F: FnMut()>(iters: usize, mut f: F) -> (f64, Vec<f64>) {
    f(); // warm-up (not counted)
    let mut s = Vec::with_capacity(iters);
    for _ in 0..iters {
        let t = Instant::now();
        f();
        s.push(t.elapsed().as_secs_f64() * 1e3);
    }
    (median(&mut s.clone()), s)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |k: &str, d: u32| -> u32 {
        args.iter().position(|a| a == k).map(|i| args[i + 1].parse().unwrap()).unwrap_or(d)
    };
    let (min, max, iters) = (arg("--min", 10), arg("--max", 20), arg("--iters", 10) as usize);
    let _ = load_backend_from_env_or_default();
    let dev = Device::new("CUDA", 0);
    set_device(&dev).expect("CUDA device 0");

    let mut out = serde_json::Map::new();
    let mut msm_d = serde_json::Map::new();
    let mut msm_h = serde_json::Map::new();
    let mut ntt_d = serde_json::Map::new();
    let mut ntt_h = serde_json::Map::new();

    // MSM: precompute_factor 1, c auto (0), batch 1, no zero bases.
    let mut cfg = MSMConfig::default();
    cfg.is_async = false;
    cfg.precompute_factor = 1;
    cfg.c = 0;
    for k in min..=max {
        let n = 1usize << k;
        let points = G1Affine::generate_random(n);
        let scalars = ScalarField::generate_random(n);
        let mut bases_d = DeviceVec::<G1Affine>::device_malloc(n).unwrap();
        precompute_bases::<G1Projective>(HostSlice::from_slice(&points), &cfg, &mut bases_d).unwrap();
        let mut scalars_d = DeviceVec::<ScalarField>::device_malloc(n).unwrap();
        scalars_d.copy_from_host(HostSlice::from_slice(&scalars)).unwrap();
        let mut res_d = DeviceVec::<G1Projective>::device_malloc(1).unwrap();
        let (md, sd) = timed(iters, || msm(&scalars_d[..], &bases_d[..], &cfg, &mut res_d[..]).unwrap());
        let mut res_h = vec![G1Projective::zero(); 1];
        let (mh, sh) = timed(iters, || msm(HostSlice::from_slice(&scalars), &bases_d[..], &cfg, HostSlice::from_mut_slice(&mut res_h)).unwrap());
        let mut chk = vec![G1Projective::zero(); 1];
        res_d.copy_to_host(HostSlice::from_mut_slice(&mut chk)).unwrap();
        let ok = chk[0] == res_h[0];
        eprintln!("msm 2^{k}: device {md:.3} ms  host-scalars {mh:.3} ms  consistent={ok}");
        msm_d.insert(k.to_string(), json!({"log2": k, "ms": md, "iters": iters, "samples_ms": sd, "consistent": ok}));
        msm_h.insert(k.to_string(), json!({"log2": k, "ms": mh, "iters": iters, "samples_ms": sh}));
    }

    // NTT: radix-2 Fr, batch 1, ordering NN (default), domain initialised once for 2^max (not timed).
    let rou = get_root_of_unity::<ScalarField>(1u64 << max).unwrap();
    let t = Instant::now();
    initialize_domain(rou, &NTTInitDomainConfig::default()).unwrap();
    let domain_ms = t.elapsed().as_secs_f64() * 1e3;
    let mut ncfg = NTTConfig::<ScalarField>::default();
    ncfg.is_async = false;
    for k in min..=max {
        let n = 1usize << k;
        let input = ScalarField::generate_random(n);
        let mut buf_d = DeviceVec::<ScalarField>::device_malloc(n).unwrap();
        buf_d.copy_from_host(HostSlice::from_slice(&input)).unwrap();
        let (fd, fsd) = timed(iters, || ntt_inplace(&mut buf_d[..], NTTDir::kForward, &ncfg).unwrap());
        let (id, isd) = timed(iters, || ntt_inplace(&mut buf_d[..], NTTDir::kInverse, &ncfg).unwrap());
        let mut out_h = vec![ScalarField::zero(); n];
        let (fh, fsh) = timed(iters, || ntt(HostSlice::from_slice(&input), NTTDir::kForward, &ncfg, HostSlice::from_mut_slice(&mut out_h)).unwrap());
        // round-trip check on host: ifft(fft(x)) == x
        let mut back = vec![ScalarField::zero(); n];
        ntt(HostSlice::from_slice(&out_h), NTTDir::kInverse, &ncfg, HostSlice::from_mut_slice(&mut back)).unwrap();
        let ok = back == input;
        eprintln!("ntt 2^{k}: device fwd {fd:.3} ms inv {id:.3} ms  host fwd {fh:.3} ms  roundtrip={ok}");
        ntt_d.insert(k.to_string(), json!({"log2": k, "fft_ms": fd, "ifft_ms": id, "iters": iters, "fft_samples_ms": fsd, "ifft_samples_ms": isd, "roundtrip_ok": ok}));
        ntt_h.insert(k.to_string(), json!({"log2": k, "fft_ms": fh, "iters": iters, "fft_samples_ms": fsh}));
    }
    out.insert("msm_g1_device".into(), Value::Object(msm_d));
    out.insert("msm_g1_host_scalars".into(), Value::Object(msm_h));
    out.insert("ntt_device".into(), Value::Object(ntt_d));
    out.insert("ntt_host".into(), Value::Object(ntt_h));
    out.insert("ntt_domain_init_ms".into(), json!(domain_ms));
    println!("{}", serde_json::to_string_pretty(&Value::Object(out)).unwrap());
}
