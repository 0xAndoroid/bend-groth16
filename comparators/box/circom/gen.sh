#!/usr/bin/env bash
# Usage: gen.sh K ART_DIR   — compile SquareChain(2^K) with circom, make the witness (x0=3),
# run snarkjs groth16 setup against ART_DIR/pot<K+1>.ptau (PSE ppot_0080 prepared phase-2 files),
# export vk. Requires circom 2.2.3 + snarkjs 0.7.6 on PATH. Output: ART_DIR/square-K/{circuit.r1cs,witness.wtns,circuit.zkey,vk.json}
set -euo pipefail
K=${1:?K}; ART=${2:?ART_DIR}
HERE=$(cd "$(dirname "$0")" && pwd)
N=$((1 << K)); P=$((K + 1)); D="$ART/square-$K"
mkdir -p "$D"
printf 'pragma circom 2.1.0;\ninclude "%s/square_chain.circom";\ncomponent main = SquareChain(%d);\n' "$HERE" "$N" > "$D/circuit.circom"
circom "$D/circuit.circom" --r1cs --wasm --sym -o "$D"
snarkjs r1cs info "$D/circuit.r1cs" | tee "$D/r1cs-info.txt"
grep -q "# of Constraints: $N\$" "$D/r1cs-info.txt" || { echo "constraint count != $N"; exit 1; }
printf '{"x0":"3"}\n' > "$D/input.json"
node "$D/circuit_js/generate_witness.js" "$D/circuit_js/circuit.wasm" "$D/input.json" "$D/witness.wtns"
snarkjs wtns check "$D/circuit.r1cs" "$D/witness.wtns"
PTAU="$ART/pot$P.ptau"
[ -f "$PTAU" ] || curl -fsSL "https://pse-trusted-setup-ppot.s3.eu-central-1.amazonaws.com/pot28_0080/ppot_0080_$P.ptau" -o "$PTAU"
NODE_OPTIONS=--max-old-space-size=65536 snarkjs groth16 setup "$D/circuit.r1cs" "$PTAU" "$D/circuit.zkey"
snarkjs zkey export verificationkey "$D/circuit.zkey" "$D/vk.json"
ls -la "$D"
