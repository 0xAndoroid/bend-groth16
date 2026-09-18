#!/bin/sh
# End-to-end prover test: K=4 must verify OK and equal arkworks' proof_ref bit for bit.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
out=$("$ROOT/bend2/scripts/prove.sh" 4)
echo "$out"
echo "$out" | grep -q '^OK$' && echo "$out" | grep -q '^EQUAL$' && echo "PASS prove K=4"
