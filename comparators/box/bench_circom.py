#!/usr/bin/env python3
"""Time snarkjs / rapidsnark Groth16 proving (CLI, cold, file-inclusive) on the shared Circom SquareChain artifacts.
Usage: bench_circom.py --prover snarkjs|rapidsnark --ks 10 14 18 20 --out bench/x.json [--art /root/art] [--runs K=N ...]
Each proof is verified with `snarkjs groth16 verify` (not timed); a failed verification aborts."""
import argparse, json, os, platform, subprocess, time, statistics, shutil

ap = argparse.ArgumentParser()
ap.add_argument("--prover", required=True, choices=["snarkjs", "rapidsnark"])
ap.add_argument("--ks", nargs="+", type=int, default=[10, 14, 18, 20])
ap.add_argument("--runs", nargs="*", default=[], help="K=N overrides; default 5 for K<=14, 3 for K=18, 2 for K=20")
ap.add_argument("--art", default=os.environ.get("ART", "/root/art"))
ap.add_argument("--out", required=True)
ap.add_argument("--cpu", default="")
ap.add_argument("--git-head", default="")
ap.add_argument("--threads", type=int, default=os.cpu_count())
ap.add_argument("--max-ms", type=float, default=600_000, help="skip larger K once a run exceeds this")
a = ap.parse_args()
runs = {10: 5, 14: 5, 18: 3, 20: 2}
for kv in a.runs:
    k, n = kv.split("="); runs[int(k)] = int(n)
snarkjs = os.environ.get("SNARKJS", "snarkjs")
rapid = os.environ.get("RAPID_PROVER", os.path.join(os.environ.get("DEV", "/root/dev"), "rapidsnark/package/bin/prover"))
versions = {"snarkjs": subprocess.run([snarkjs, "--version"], capture_output=True, text=True).stdout.strip().split()[-1] if shutil.which(snarkjs) else "0.7.6", "circom": "2.2.3", "node": platform.python_version() and subprocess.run(["node", "--version"], capture_output=True, text=True).stdout.strip()}
if a.prover == "rapidsnark":
    versions["rapidsnark"] = "v0.0.8"
doc = {"schema": 1, "framework": a.prover, "versions": versions, "host": platform.node(), "cpu": a.cpu, "threads": a.threads,
       "git_head": a.git_head, "updated": "", "prove": {},
       "notes": ("snarkjs groth16 prove CLI (node, wasm+workers); " if a.prover == "snarkjs" else "rapidsnark prover CLI (C++ x86_64 asm, thread pool + OpenMP); ")
                + "wall time of one process launch = zkey+wtns load from disk + prove + JSON write (cold/file-inclusive). No witness solving (wtns pre-generated). Verified with snarkjs groth16 verify (untimed)."}
if os.path.exists(a.out):
    try:
        doc["prove"] = json.load(open(a.out)).get("prove", {})
    except Exception:
        pass
env = dict(os.environ, NODE_OPTIONS="--max-old-space-size=65536")
stop = False
for k in a.ks:
    if stop:
        break
    d = f"{a.art}/square-{k}"
    zkey, wtns, vk = f"{d}/circuit.zkey", f"{d}/witness.wtns", f"{d}/vk.json"
    proof, public = f"{d}/proof-{a.prover}.json", f"{d}/public-{a.prover}.json"
    cmd = [snarkjs, "groth16", "prove", zkey, wtns, proof, public] if a.prover == "snarkjs" else [rapid, zkey, wtns, proof, public]
    samples = []
    for i in range(runs.get(k, 3)):
        t = time.perf_counter()
        r = subprocess.run(cmd, capture_output=True, text=True, env=env)
        ms = (time.perf_counter() - t) * 1e3
        if r.returncode != 0:
            raise SystemExit(f"{a.prover} K={k} failed: {r.stderr[-500:]}")
        v = subprocess.run([snarkjs, "groth16", "verify", vk, public, proof], capture_output=True, text=True, env=env)
        if "OK!" not in v.stdout:
            raise SystemExit(f"verify failed K={k}: {v.stdout} {v.stderr}")
        samples.append(round(ms, 2))
        print(f"{a.prover} K={k} run {i}: {ms:.1f} ms (verify OK)", flush=True)
        if ms > a.max_ms:
            stop = True
            break
    doc["prove"][str(k)] = {"log2": k, "num_constraints": 1 << k, "ms": statistics.median(samples), "iters": len(samples),
                            "samples_ms": samples, "verified": True, "zkey_bytes": os.path.getsize(zkey),
                            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    doc["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    json.dump(doc, open(a.out, "w"), indent=2); open(a.out, "a").write("\n")
