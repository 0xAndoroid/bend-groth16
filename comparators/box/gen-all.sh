#!/usr/bin/env bash
# Circom artifacts for K in 10 14 18 20 under /root/art/square-K (zkey/wtns shared by rapidsnark, snarkjs, ICICLE-SNARK).
set -euxo pipefail
export PATH=/usr/local/go/bin:/root/tools:/root/tools/node_modules/.bin:$PATH
REPO=${REPO:-/root/w1}
for k in ${KS:-10 14 18 20}; do
  /usr/bin/time -v "$REPO/comparators/box/circom/gen.sh" "$k" /root/art 2>&1 | tee /root/art/gen-$k.log | grep -E 'Constraints|Wires|Elapsed|Maximum resident|OK|error' || true
done
touch /root/done-gen
