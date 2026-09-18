#!/usr/bin/env python3
"""Assemble bench/box-gpu-primitives.json from: our icicle-prim binary (ICICLE v4.0.0), sppark's poc/msm-cuda
criterion bench (BENCH_NPOW=k), and our sppark ntt_timer example. Usage: primitives.py --out bench/box-gpu-primitives.json"""
import argparse, json, os, platform, re, subprocess, time

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--min", type=int, default=10); ap.add_argument("--max", type=int, default=20)
ap.add_argument("--iters", type=int, default=10)
ap.add_argument("--cpu", default=""); ap.add_argument("--gpu", default=""); ap.add_argument("--git-head", default="")
ap.add_argument("--repo", default="/root/w1"); ap.add_argument("--dev", default="/root/dev"); ap.add_argument("--art", default="/root/art")
ap.add_argument("--skip-sppark", action="store_true")
a = ap.parse_args()
doc = {"schema": 1, "framework": "gpu-primitives", "host": platform.node(), "cpu": a.cpu, "gpu": a.gpu, "git_head": a.git_head, "updated": "",
       "icicle": {}, "sppark": {}}

# ICICLE v4 (open-icicle v4.0.0), CUDA backend built with -DCUDA_ARCH=120 into /root/art/icicle4-install
env = dict(os.environ, ICICLE_BACKEND_INSTALL_DIR=f"{a.art}/icicle4-install/lib/backend", LD_LIBRARY_PATH=f"{a.art}/icicle4-install/lib")
r = subprocess.run([f"{a.repo}/comparators/gpu/icicle-prim/target/release/icicle-prim", "--min", str(a.min), "--max", str(a.max), "--iters", str(a.iters)],
                   capture_output=True, text=True, env=env)
print(r.stderr, flush=True)
if r.returncode != 0:
    raise SystemExit("icicle-prim failed")
doc["icicle"] = json.loads(r.stdout)
doc["icicle"]["versions"] = {"open-icicle": "v4.0.0", "cuda_arch": "120", "build": "cmake -DCURVE=bn254 -DCUDA_BACKEND=local -DCUDA_ARCH=120 (G2/ECNTT/FRI/POSEIDON/SUMCHECK off)"}
doc["icicle"]["notes"] = ("Synchronous calls (is_async=false; wall includes launch + device sync). msm_g1_device: scalars+bases device-resident, "
                          "precompute_factor=1, c auto, batch 1 -> kernel-only. msm_g1_host_scalars: scalars H2D per call, bases cached (gnark-style). "
                          "ntt_device: in-place device buffer, radix-2 Fr, ordering NN (kernel-only). ntt_host: host in/out (H2D+D2H). "
                          f"Domain (twiddles) initialised once for 2^{a.max}, not timed (ntt_domain_init_ms). Median of {a.iters} after 1 warm-up.")
doc["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump(doc, open(a.out, "w"), indent=2)

if not a.skip_sppark:
    # sppark v0.1.15 poc/msm-cuda: criterion bench, host-inclusive (points + scalars copied H2D each iteration)
    msm = {}
    for k in range(a.min, a.max + 1):
        r = subprocess.run(["cargo", "bench", "-q", "--features", "bn254", "--bench", "msm", "--", "--noplot", "--warm-up-time", "1", "--measurement-time", "3"],
                           cwd=f"{a.dev}/sppark/poc/msm-cuda", capture_output=True, text=True, env=dict(os.environ, BENCH_NPOW=str(k)))
        m = re.search(r"time:\s+\[([0-9.]+) (\S+) ([0-9.]+) (\S+) ([0-9.]+) (\S+)\]", r.stdout)
        if not m:
            print(f"sppark msm 2^{k}: no criterion line\n{r.stdout[-800:]}\n{r.stderr[-800:]}", flush=True)
            msm[str(k)] = {"log2": k, "error": (r.stderr[-400:] or r.stdout[-400:])}
            continue
        unit = {"ns": 1e-6, "µs": 1e-3, "us": 1e-3, "ms": 1, "s": 1e3}
        lo, mid, hi = float(m.group(1)) * unit[m.group(2)], float(m.group(3)) * unit[m.group(4)], float(m.group(5)) * unit[m.group(6)]
        print(f"sppark msm 2^{k}: {mid:.3f} ms [{lo:.3f}, {hi:.3f}]", flush=True)
        msm[str(k)] = {"log2": k, "ms": round(mid, 4), "ci_lo_ms": round(lo, 4), "ci_hi_ms": round(hi, 4), "criterion_sample_size": 20}
    doc["sppark"]["msm_g1_host"] = msm
    # sppark NTT: our example timer (in-place host slice -> H2D + kernel + D2H per call)
    r = subprocess.run(["cargo", "run", "-q", "--release", "--features", "bn254", "--example", "ntt_timer", "--", str(a.min), str(a.max), str(a.iters)],
                       cwd=f"{a.dev}/sppark/poc/ntt-cuda", capture_output=True, text=True)
    print(r.stderr, flush=True)
    doc["sppark"]["ntt_host"] = json.loads(r.stdout) if r.returncode == 0 else {"error": r.stderr[-800:]}
    doc["sppark"]["versions"] = {"sppark": "v0.1.15", "cuda_arch": "sm_120 via sppark build.rs nvcc probe (compute_120,code=sm_120)"}
    doc["sppark"]["notes"] = ("msm_g1_host: poc/msm-cuda criterion bench `multi_scalar_mult_arkworks` (ark 0.3 affine points + BigInteger256 scalars), "
                              "each iteration copies points AND scalars H2D and syncs -> host-inclusive, not kernel-only; no device-resident API in the PoC. "
                              f"ntt_host: poc/ntt-cuda `NTT`/`iNTT` in-place on a host slice (H2D + kernel + D2H), NN order, median of {a.iters}.")
doc["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump(doc, open(a.out, "w"), indent=2); open(a.out, "a").write("\n")
