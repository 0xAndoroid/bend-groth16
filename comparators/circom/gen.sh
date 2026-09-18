#!/usr/bin/env bash
# Usage: gen.sh K [OUT_DIR]
# Emits square_chain_K.circom (main = SquareChain(2^K)), compiles it with
# circom (--r1cs --wasm --sym) into OUT_DIR/square_chain_K/, prints `snarkjs r1cs info`.
# Requires `circom` and `snarkjs` on PATH (or CIRCOM / SNARKJS env overrides).
set -euo pipefail
K=${1:?K (log2 constraints)}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${2:-$HERE/build}
CIRCOM=${CIRCOM:-circom}
SNARKJS=${SNARKJS:-snarkjs}
N=$((1 << K))
mkdir -p "$OUT/square_chain_$K"
MAIN="$OUT/square_chain_$K/square_chain_$K.circom"
cat > "$MAIN" <<CIRCUIT
pragma circom 2.1.0;
include "$HERE/square_chain.circom";
component main = SquareChain($N);
CIRCUIT
"$CIRCOM" "$MAIN" --r1cs --wasm --sym -o "$OUT/square_chain_$K"
"$SNARKJS" r1cs info "$OUT/square_chain_$K/square_chain_$K.r1cs"
