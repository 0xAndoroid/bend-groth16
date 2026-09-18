#!/bin/sh
# Build + run every bend2 test against data/vectors/bend/*.bin. Run from anywhere.
# Vectors: `groth16-ref vectors data/vectors` then `bend2/tools/export_bin.py` (or the
# fallback `uv run python bend2/gen/vectors_to_bin.py`).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${TMPDIR:-/tmp}/bend2-tests
mkdir -p "$OUT"
export BEND_NO_TELEMETRY=1
BEND=${BEND:-$HOME/.bend/bin/bend}
[ -f "$ROOT/data/vectors/bend/fr_ops.bin" ] || (cd "$ROOT" && uv run python bend2/gen/vectors_to_bin.py)
fail=0
for t in test_fr test_fq test_g1 test_g2 probe_show; do
  (cd "$ROOT/bend2/tests" && "$BEND" "$t.bend" -o "$OUT/$t")
  printf '%s: ' "$t"
  out=$(cd "$ROOT" && "$OUT/$t")
  echo "$out" | head -1
  case "$t" in probe_show) ;; *) echo "$out" | grep -q '^PASS' || fail=1 ;; esac
done
exit $fail
