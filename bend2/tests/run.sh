#!/bin/sh
# Build + run every bend2 test against data/vectors/bend/*.bin and data/{4,10}/bend, then the
# end-to-end K=4 prove (tests/test_prove.sh). Run from anywhere.
# Vectors: `groth16-ref vectors --out data/vectors` then `bend2/tools/export_bin.py --vectors data/vectors`;
# QAP refs via bend2/gen/ref_qap.py.
# Exit 1 unless every test exits 0 and prints only PASS lines (no FAIL, no `PASS 0`).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${TMPDIR:-/tmp}/bend2-tests
mkdir -p "$OUT"
export BEND_NO_TELEMETRY=1
BEND=${BEND:-$HOME/.bend/bin/bend}
[ -f "$ROOT/data/vectors/bend/fr_ops.bin" ] || (cd "$ROOT" && uv run python bend2/tools/export_bin.py --vectors data/vectors)
for k in 4 10; do
  [ -f "$ROOT/data/$k/bend/h_ref.bin" ] || (cd "$ROOT" && uv run python bend2/gen/ref_qap.py "data/$k")
done
fail=0
for f in "$ROOT"/data/vectors/bend/*.bin; do
  [ -s "$f" ] || { echo "empty vector file: $f"; fail=1; }
done
# run "$name" ENV=... : run $OUT/$name with the env; PASS iff exit 0 and every line is a PASS line
run() {
  name=$1
  shift
  printf '%s%s: ' "$name" "${1:+ $1}"
  rc=0
  out=$(cd "$ROOT" && env "$@" "$OUT/$name" 2>&1) || rc=$?
  echo "$out" | head -1
  [ "$rc" -eq 0 ] && [ -n "$out" ] && ! echo "$out" | grep -qvE '^PASS ' && ! echo "$out" | grep -qE 'FAIL|^PASS 0$' || { echo "  -> FAIL (exit $rc)"; fail=1; }
}
for t in test_fr test_fq test_g1 test_g2 test_ntt test_msm probe_show; do
  (cd "$ROOT/bend2/tests" && "$BEND" "$t.bend" -o "$OUT/$t")
  case "$t" in
    probe_show) printf '%s: ' "$t"; (cd "$ROOT" && "$OUT/$t" | head -1) ;;
    test_ntt) run test_ntt; run test_ntt K=4; run test_ntt K=10 ;;
    *) run "$t" ;;
  esac
done
printf 'test_prove: '
out=$(sh "$ROOT/bend2/tests/test_prove.sh" 2>&1) || fail=1
echo "$out" | tail -1
echo "$out" | grep -q '^PASS prove K=4$' || { echo "  -> FAIL"; fail=1; }
exit $fail
