#!/bin/sh
# Full-prover benchmark: runs bend2/scripts/prove.sh RUNS times and prints one JSON line per run
# (phase ms from the prover's `T` lines, OK/EQUAL verdicts, load average) — bench/bend2-*.json inputs.
#   bend2/scripts/bench_prover.sh run CFG RUNS K [binary args, e.g. --threads 1]     CFG = cpu1|cpu_all|gpu
#   bend2/scripts/bench_prover.sh merge META.json OUT.json runs.jsonl
# `merge` builds the bench/README.md-style file: META.json supplies host/cpu/threads/versions and the
# msm_g1/ntt primitive tables; prove.<log2>.<cfg> gets the median total, samples and median phases.
# PROVE=<path> swaps in another prove.sh (the box copy uses python3 + the prebuilt groth16-ref);
# PY=<python> picks the interpreter for merge (default: uv run python, else python3).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PROVE=${PROVE:-$HERE/prove.sh}
mode=$1
shift
case "$mode" in
run)
  cfg=$1; runs=$2; k=$3; shift 3
  i=0
  while [ $i -lt "$runs" ]; do
    i=$((i + 1))
    load=$(uptime | sed 's/.*load averages*: *//; s/,//g')
    out=$("$PROVE" "$k" "$@" 2>&1) || true
    phases=$(echo "$out" | awk '/^T /{printf "%s\"%s\":%s", (n++ ? "," : ""), $2, $3}')
    ok=false; echo "$out" | grep -qx OK && ok=true
    eq=false; echo "$out" | grep -qx EQUAL && eq=true
    echo "{\"k\":$k,\"cfg\":\"$cfg\",\"args\":\"$*\",\"phases_ms\":{$phases},\"ok\":$ok,\"equal\":$eq,\"loadavg\":\"$load\"}"
  done
  ;;
merge)
  if [ -z "${PY:-}" ]; then
    command -v uv >/dev/null 2>&1 && PY="uv run python" || PY=python3
  fi
  $PY - "$1" "$2" "$3" <<'PY'
import json, statistics, sys
meta = json.load(open(sys.argv[1]))
runs = [json.loads(l) for l in open(sys.argv[3]) if l.strip()]
prove = {}
for r in runs:
    prove.setdefault(str(r["k"]), {}).setdefault(r["cfg"], []).append(r)
out = {"schema": 1, "framework": "bend2", **meta, "prove": {}}
for k, cfgs in sorted(prove.items(), key=lambda kv: int(kv[0])):
    entry = {"log2": int(k), "num_constraints": 2 ** int(k)}
    for cfg, rs in cfgs.items():
        names = [n for n in rs[0]["phases_ms"] if all(n in r["phases_ms"] for r in rs)]
        entry[cfg] = {
            "ms": statistics.median(r["phases_ms"].get("total", 0) for r in rs),
            "iters": len(rs),
            "samples_ms": [r["phases_ms"].get("total", 0) for r in rs],
            "phases_ms": {n: statistics.median(r["phases_ms"][n] for r in rs) for n in names if n != "total"},
            "ok": all(r["ok"] for r in rs),
            "equal": all(r["equal"] for r in rs),
            "args": rs[0]["args"],
            "loadavg": [r["loadavg"] for r in rs],
        }
    out["prove"][k] = entry
json.dump(out, open(sys.argv[2], "w"), indent=1)
open(sys.argv[2], "a").write("\n")
PY
  ;;
*) echo "usage: $0 run CFG RUNS K [args] | merge META.json OUT.json RUNS.jsonl" >&2; exit 2 ;;
esac
