#!/bin/sh
# Type-check every proof file in bend2/proofs with Bend 2 (each must print "All terms check.").
# Run from anywhere: sh bend2/proofs/check.sh
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
export BEND_NO_TELEMETRY=1
BEND=${BEND:-$HOME/.bend/bin/bend}
fail=0
for f in "$DIR"/*.bend; do
  printf '%s: ' "$(basename "$f")"
  out=$(cd "$DIR" && "$BEND" "$(basename "$f")" 2>&1) || true
  echo "$out" | tail -1
  [ "$out" = "All terms check." ] || fail=1
done
exit $fail
