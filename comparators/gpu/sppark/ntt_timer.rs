// sppark v0.1.15 poc/ntt-cuda BN254 Fr NTT timer (the PoC ships no BN254 timing bench).
// Copy to poc/ntt-cuda/examples/ntt_timer.rs; run: cargo run --release --features bn254 --example ntt_timer -- 10 20 10
// `ntt_cuda::NTT` is in-place on a HOST slice: each sample includes H2D + kernel + D2H and a device sync.
use ark_bn254::Fr;
use ark_ff::UniformRand;
use sppark::NTTInputOutputOrder;
use std::time::Instant;

fn main() {
    let a: Vec<u32> = std::env::args().skip(1).map(|s| s.parse().unwrap()).collect();
    let (min, max, iters) = (a.get(0).copied().unwrap_or(10), a.get(1).copied().unwrap_or(20), a.get(2).copied().unwrap_or(10) as usize);
    let mut rng = ark_std::test_rng();
    print!("{{");
    for k in min..=max {
        let n = 1usize << k;
        let orig: Vec<Fr> = (0..n).map(|_| Fr::rand(&mut rng)).collect();
        let mut v = orig.clone();
        ntt_cuda::NTT(0, &mut v, NTTInputOutputOrder::NN); // warm-up
        let mut fwd = Vec::new();
        let mut inv = Vec::new();
        for _ in 0..iters {
            let t = Instant::now();
            ntt_cuda::NTT(0, &mut v, NTTInputOutputOrder::NN);
            fwd.push(t.elapsed().as_secs_f64() * 1e3);
            let t = Instant::now();
            ntt_cuda::iNTT(0, &mut v, NTTInputOutputOrder::NN);
            inv.push(t.elapsed().as_secs_f64() * 1e3);
        }
        let ok = v == orig; // warm-up fwd is undone by nothing: v = NTT^{iters+1} iNTT^{iters}(orig) -> compare after one more iNTT
        let ok = ok || { ntt_cuda::iNTT(0, &mut v, NTTInputOutputOrder::NN); v == orig };
        let med = |s: &mut Vec<f64>| { s.sort_by(|a, b| a.partial_cmp(b).unwrap()); if s.len() % 2 == 1 { s[s.len() / 2] } else { (s[s.len() / 2 - 1] + s[s.len() / 2]) / 2.0 } };
        let (mf, mi) = (med(&mut fwd.clone()), med(&mut inv.clone()));
        eprintln!("ntt 2^{k}: fwd {mf:.3} ms inv {mi:.3} ms roundtrip={ok}");
        print!("{}\"{k}\":{{\"log2\":{k},\"fft_ms\":{mf},\"ifft_ms\":{mi},\"iters\":{iters},\"fft_samples_ms\":{fwd:?},\"ifft_samples_ms\":{inv:?},\"roundtrip_ok\":{ok}}}", if k == min { "" } else { "," });
    }
    println!("}}");
}
