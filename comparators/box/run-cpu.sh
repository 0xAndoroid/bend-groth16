#!/usr/bin/env bash
# Box-CPU comparator sweep -> bench/box-cpu-{gnark,rapidsnark,snarkjs}.json. Run one prover at a time, quiet box.
set -euxo pipefail
DEV=${DEV:-/root/dev}; ART=${ART:-/root/art}; TOOLS=${TOOLS:-/root/tools}
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export PATH=/usr/local/go/bin:$TOOLS:$TOOLS/node_modules/.bin:$PATH
OUT=$REPO/bench; mkdir -p $OUT
CPU=$(lscpu | sed -n 's/^Model name: *//p'); HEAD=$(git -C $REPO rev-parse --short HEAD 2>/dev/null || echo box)
# gnark CPU: all cores at every K; GOMAXPROCS=1 at K<=14 (stored in a separate file)
$ART/gnark-cpu -k 10,14 -iters 5 -out $OUT/box-cpu-gnark.json -cpu "$CPU" -git-head "$HEAD"
$ART/gnark-cpu -k 18,20 -iters 3 -out $OUT/box-cpu-gnark.json -cpu "$CPU" -git-head "$HEAD"
GOMAXPROCS=1 $ART/gnark-cpu -k 10,14 -iters 5 -out $OUT/box-cpu-gnark-1thread.json -cpu "$CPU" -git-head "$HEAD"
# rapidsnark v0.0.8 + snarkjs 0.7.6 on the shared Circom artifacts
RAPID_PROVER=$DEV/rapidsnark/package/bin/prover $REPO/comparators/box/bench_circom.py --prover rapidsnark --ks 10 14 18 20 --out $OUT/box-cpu-rapidsnark.json --cpu "$CPU" --git-head "$HEAD"
$REPO/comparators/box/bench_circom.py --prover snarkjs --ks 10 14 18 20 --runs 18=2 20=1 --out $OUT/box-cpu-snarkjs.json --cpu "$CPU" --git-head "$HEAD" --max-ms 600000
touch $ART/done-cpu
