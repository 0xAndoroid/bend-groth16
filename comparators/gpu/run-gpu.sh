#!/usr/bin/env bash
# GPU comparator sweep -> bench/box-gpu-{gnark-icicle,icicle-snark,primitives}.json
set -euxo pipefail
DEV=${DEV:-/root/dev}; ART=${ART:-/root/art}; TOOLS=${TOOLS:-/root/tools}
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export PATH=$HOME/.cargo/bin:/usr/local/go/bin:$TOOLS:$TOOLS/node_modules/.bin:$PATH
OUT=$REPO/bench; mkdir -p $OUT
CPU=$(lscpu | sed -n 's/^Model name: *//p'); GPU=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader); HEAD=$(git -C $REPO rev-parse --short HEAD 2>/dev/null || echo box)
# (a) gnark v0.16.3 + icicle-gnark v3.2.2, PK vectors not pinned (default) and pinned
export ICICLE_BACKEND_INSTALL_DIR=$ART/gnark-install/lib/backend LD_LIBRARY_PATH=$ART/gnark-install/lib
$ART/gnark-icicle -gpu -k 10,14 -iters 5 -out $OUT/box-gpu-gnark-icicle.json -cpu "$CPU" -gpu-name "$GPU" -git-head "$HEAD"
$ART/gnark-icicle -gpu -k 18,20 -iters 3 -out $OUT/box-gpu-gnark-icicle.json -cpu "$CPU" -gpu-name "$GPU" -git-head "$HEAD"
$ART/gnark-icicle -gpu -pin -k 10,14 -iters 5 -out $OUT/box-gpu-gnark-icicle-pinned.json -cpu "$CPU" -gpu-name "$GPU" -git-head "$HEAD"
$ART/gnark-icicle -gpu -pin -k 18,20 -iters 3 -out $OUT/box-gpu-gnark-icicle-pinned.json -cpu "$CPU" -gpu-name "$GPU" -git-head "$HEAD"
# (b) ICICLE-SNARK @bf00385 on the shared Circom zkey/wtns
ICICLE_BACKEND_INSTALL_DIR=$ART/snark-install/lib/backend LD_LIBRARY_PATH=$ART/snark-install/lib \
  $REPO/comparators/gpu/icicle_snark_bench.py --ks 10 14 18 20 --warm 5 --out $OUT/box-gpu-icicle-snark.json --cpu "$CPU" --gpu "$GPU" --git-head "$HEAD"
# (c) primitives: ICICLE v4 MSM/NTT + sppark MSM/NTT
$REPO/comparators/gpu/primitives.py --out $OUT/box-gpu-primitives.json --cpu "$CPU" --gpu "$GPU" --git-head "$HEAD"
touch $ART/done-gpu
