#!/usr/bin/env python3
"""Time Groth16 proving with snarkjs or rapidsnark on the SquareChain circuits.

Usage: bench.py --prover snarkjs|rapidsnark --ks 10 14 --runs 3 --out bench/x.json
Env: BENCH_DIR (zkeys/witnesses: $BENCH_DIR/zkey/square_chain_K.zkey,
$BENCH_DIR/wtns/square_chain_K.wtns), SNARKJS (snarkjs CLI), RAPIDSNARK (prover binary).
Every proof is verified with `snarkjs groth16 verify` (not timed); a failed verify aborts.
"""
import argparse, json, os, platform, statistics, subprocess, sys, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("--prover", required=True, choices=["snarkjs", "rapidsnark"])
ap.add_argument("--ks", type=int, nargs="+", required=True)
ap.add_argument("--runs", type=int, default=3)
ap.add_argument("--out", required=True)
ap.add_argument("--version", default="")
ap.add_argument("--threads", type=int, default=os.cpu_count())
ap.add_argument("--host", default="macmini")
args = ap.parse_args()

bench = os.environ["BENCH_DIR"]
snarkjs = os.environ.get("SNARKJS", "snarkjs")
rapidsnark = os.environ.get("RAPIDSNARK", "prover")
cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip() \
    if platform.system() == "Darwin" else platform.processor()

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"FAILED: {' '.join(cmd)}\n{r.stdout}\n{r.stderr}")
    return r.stdout

results = []
tmp = tempfile.mkdtemp(prefix="bench_", dir=os.environ.get("TMPDIR"))
for k in args.ks:
    zkey = f"{bench}/zkey/square_chain_{k}.zkey"
    vkey = f"{bench}/zkey/square_chain_{k}.vkey.json"
    wtns = f"{bench}/wtns/square_chain_{k}.wtns"
    proof, public = f"{tmp}/proof_{k}.json", f"{tmp}/public_{k}.json"
    if args.prover == "snarkjs":
        cmd = [snarkjs, "groth16", "prove", zkey, wtns, proof, public]
    else:
        cmd = [rapidsnark, zkey, wtns, proof, public]
    ms = []
    for i in range(args.runs):
        t0 = time.perf_counter()
        run(cmd)
        ms.append(round((time.perf_counter() - t0) * 1000, 1))
        out = run([snarkjs, "groth16", "verify", vkey, public, proof])
        if "OK!" not in out:
            sys.exit(f"verify failed at K={k} run {i}: {out}")
        print(f"{args.prover} K={k} run {i}: {ms[-1]} ms (verify OK)", flush=True)
    results.append({"log2": k, "constraints": 1 << k, "prove_ms": ms,
                    "median_ms": round(statistics.median(ms), 1)})

doc = {"host": args.host, "cpu": cpu, "threads": args.threads, "prover": args.prover,
       "version": args.version, "circuit": "SquareChain(2^K), BN254, x0=12345678901234567890",
       "results": results}
with open(args.out, "w") as f:
    json.dump(doc, f, indent=1)
    f.write("\n")
print(f"wrote {args.out}")
