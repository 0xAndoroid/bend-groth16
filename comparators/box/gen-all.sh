#!/usr/bin/env bash
# Circom artifacts for K in 10 14 18 20 under $ART/square-K (zkey/wtns shared by rapidsnark, snarkjs, ICICLE-SNARK).
set -euxo pipefail
DEV=${DEV:-/root/dev}; ART=${ART:-/root/art}; TOOLS=${TOOLS:-/root/tools}
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export PATH=/usr/local/go/bin:$TOOLS:$TOOLS/node_modules/.bin:$PATH

for k in ${KS:-10 14 18 20}; do
  /usr/bin/time -v "$REPO/comparators/box/circom/gen.sh" "$k" "$ART" 2>&1 | tee "$ART/gen-$k.log" | grep -E 'Constraints|Wires|Elapsed|Maximum resident|OK|error' || true
done
touch $ART/done-gen
