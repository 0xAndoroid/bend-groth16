#!/usr/bin/env python3
"""Drive one ICICLE-SNARK (bf00385) worker over stdin: per K one cold `prove` (parses + caches the zkey on the
device) then N warm proves on the same Circom zkey/wtns. Records the worker's own `proof took:` timer (witness
load + prove + JSON write; zkey cached) and the driver's wall time around the command. Verifies with snarkjs.
Usage: icicle_snark_bench.py --ks 10 14 18 20 --out bench/box-gpu-icicle-snark.json [--device CUDA] [--warm 5]"""
import argparse, json, os, platform, re, subprocess, time, statistics

ap = argparse.ArgumentParser()
ap.add_argument("--ks", nargs="+", type=int, default=[10, 14, 18, 20])
ap.add_argument("--warm", type=int, default=5)
ap.add_argument("--art", default=os.environ.get("ART", "/root/art"))
ap.add_argument("--bin", default=os.path.join(os.environ.get("DEV", "/root/dev"), "icicle-snark/target/release/icicle-snark"))
ap.add_argument("--device", default="CUDA")
ap.add_argument("--out", required=True)
ap.add_argument("--cpu", default=""); ap.add_argument("--gpu", default=""); ap.add_argument("--git-head", default="")
a = ap.parse_args()
snarkjs = os.environ.get("SNARKJS", "snarkjs")

def dur_ms(s):  # Rust Duration Debug: 1.234s | 123.4ms | 12.3µs
    m = re.search(r"proof took: ([0-9.]+)(s|ms|µs|us|ns)", s)
    v, u = float(m.group(1)), m.group(2)
    return v * {"s": 1e3, "ms": 1, "µs": 1e-3, "us": 1e-3, "ns": 1e-6}[u]

w = subprocess.Popen([a.bin], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

def run(line):
    t = time.perf_counter()
    w.stdin.write(line + "\n"); w.stdin.flush()
    buf = ""
    while True:
        ch = w.stdout.readline() if False else w.stdout.read(1)
        if ch == "":
            raise SystemExit("worker died:\n" + buf)
        buf += ch
        if "COMMAND_COMPLETED" in buf:
            break
    return (time.perf_counter() - t) * 1e3, buf

doc = {"schema": 1, "framework": "icicle-snark", "versions": {"icicle-snark": "bf00385", "circom": "2.2.3", "snarkjs": "0.7.6"},
       "host": platform.node(), "cpu": a.cpu, "gpu": a.gpu, "threads": os.cpu_count(), "git_head": a.git_head, "updated": "", "prove": {},
       "notes": f"ICICLE-SNARK worker, --device {a.device}, one long-lived process; ms = worker's `proof took` timer with zkey cached on device (includes .wtns read from disk + proof/public JSON write; excludes zkey parse). first_prove_ms = cold command incl. zkey parse + H2D. wall_ms = driver-side wall around the command. Experimental (README excludes production use). Verified with snarkjs groth16 verify."}
for k in a.ks:
    d = f"{a.art}/square-{k}"
    line = f"prove --witness {d}/witness.wtns --zkey {d}/circuit.zkey --proof {d}/proof-icicle.json --public {d}/public-icicle.json --device {a.device}"
    wall0, out0 = run(line)
    cold = dur_ms(out0)
    print(f"K={k} cold: {cold:.1f} ms (wall {wall0:.1f})", flush=True)
    samples, walls = [], []
    for i in range(a.warm):
        wall, out = run(line)
        samples.append(round(dur_ms(out), 2)); walls.append(round(wall, 2))
        print(f"K={k} warm[{i}]: {samples[-1]} ms (wall {wall:.1f})", flush=True)
    v = subprocess.run([snarkjs, "groth16", "verify", f"{d}/vk.json", f"{d}/public-icicle.json", f"{d}/proof-icicle.json"], capture_output=True, text=True)
    ok = "OK!" in v.stdout
    print(f"K={k} verify: {ok}", flush=True)
    doc["prove"][str(k)] = {"log2": k, "num_constraints": 1 << k, "ms": statistics.median(samples), "iters": len(samples), "samples_ms": samples,
                            "wall_ms": statistics.median(walls), "wall_samples_ms": walls, "first_prove_ms": round(cold, 2), "first_wall_ms": round(wall0, 2),
                            "verified": ok, "device": a.device, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if not ok:
        raise SystemExit("verification failed")
w.stdin.write("exit\n"); w.stdin.flush(); w.wait(timeout=60)
doc["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump(doc, open(a.out, "w"), indent=2); open(a.out, "a").write("\n")
