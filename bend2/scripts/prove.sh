#!/bin/sh
# Build bend2/prove.bend, prove data/<K>, verify with the arkworks harness, compare to proof_ref.
# Usage: bend2/scripts/prove.sh K [binary args, e.g. --threads 1]
# Prints the prover's T lines, then OK|INVALID and EQUAL|DIFFERENT; exit 1 unless OK + EQUAL.
# Data: $BENDG_DATA_ROOT, else <repo>/data (gitignored).
set -eu
K=$1
shift
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DATA=${BENDG_DATA_ROOT:-$ROOT/data}
OUT=${TMPDIR:-/tmp}/bend-groth16
mkdir -p "$OUT"
export BEND_NO_TELEMETRY=1
BEND=${BEND:-$HOME/.bend/bin/bend}
"$BEND" "$ROOT/bend2/prove.bend" -o "$OUT/prove_bin"
BENDG_DATA="$DATA/$K/bend" "$OUT/prove_bin" "$@" > "$OUT/prove_$K.txt"
grep '^T ' "$OUT/prove_$K.txt"
status=0
eq=$(grep -E '^[ABC] ' "$OUT/prove_$K.txt" | (cd "$ROOT" && uv run python bend2/tools/proof_to_json.py -o "$OUT/proof_$K.json" --compare "$DATA/$K/proof_ref.json") 2>&1 | grep -c ': EQUAL$' || true)
[ "$eq" = 3 ] && cmp=EQUAL || cmp=DIFFERENT
ver=$(cargo run --release -q --manifest-path "$ROOT/ref/Cargo.toml" -- verify --vk "$DATA/$K/vk.json" --proof "$OUT/proof_$K.json" --public "$DATA/$K/public.json" | tail -1)
echo "$ver"
echo "$cmp"
[ "$ver" = OK ] && [ "$cmp" = EQUAL ] || status=1
exit $status
