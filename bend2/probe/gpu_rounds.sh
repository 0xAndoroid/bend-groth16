#!/bin/sh
# Build a Bend 2 program with the runtime's scheduler rounds instrumented.
# Usage: bend2/probe/gpu_rounds.sh prog.bend OUTDIR   ->  OUTDIR/<prog> (+ <prog>.gpu)
# Run the binary with BEND_ROUNDS=1 to get, on stderr, one line per cube_run:
#   rounds=R frontier_sum=S frontier_max=M f1=A f<=128=B f<=1024=C f<=16384=D f>16384=E ms=T
# R = host-synchronised scheduler rounds (each = grow/work/pack kernels in one Metal
# command buffer, or two pool_turn phases on the CPU); f = tasks handed over at the
# start of a round, before its grow kernels fork them further. Same host clang flags as
# ~/.bend/current/bend2/main.ts cli_build (macOS, `!` program). Bend 2.0.5 only.
set -eu
SRC=$1
OUT=$2
NAME=$(basename "$SRC" .bend)
mkdir -p "$OUT"
export BEND_NO_TELEMETRY=1
"${BEND:-$HOME/.bend/bin/bend}" "$SRC" -o "$OUT/$NAME.c"
"${PYTHON:-python3}" - "$OUT/$NAME.c" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
old = """static void cube_run(Corpus H, bool gpu) {
  for (;;) {
    u32 f = a32_load(a32_at(H, H_CURSOR));
    a32_store(a32_at(H, H_CURSOR), 0);
    if (root_done(H)) {
      return;
    }
    if (f == 0) {
      err_fail("frontier drained without a result");
    }
    if (gpu) {
      gpu_pass(f);
    } else {"""
new = """static double rounds_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}
static void cube_run(Corpus H, bool gpu) {
  static int trace = -1;
  if (trace < 0) {
    trace = getenv("BEND_ROUNDS") != NULL;
  }
  u64 rounds = 0, fsum = 0, fmax = 0, h1 = 0, h128 = 0, h1k = 0, h16k = 0, hbig = 0;
  double t0 = rounds_now();
  for (;;) {
    u32 f = a32_load(a32_at(H, H_CURSOR));
    a32_store(a32_at(H, H_CURSOR), 0);
    if (root_done(H)) {
      if (trace) {
        fprintf(stderr, "rounds=%llu frontier_sum=%llu frontier_max=%llu f1=%llu f<=128=%llu f<=1024=%llu f<=16384=%llu f>16384=%llu ms=%.1f %s\\n",
          (unsigned long long)rounds, (unsigned long long)fsum, (unsigned long long)fmax,
          (unsigned long long)h1, (unsigned long long)h128, (unsigned long long)h1k,
          (unsigned long long)h16k, (unsigned long long)hbig, rounds_now() - t0, gpu ? "gpu" : "cpu");
      }
      return;
    }
    if (f == 0) {
      err_fail("frontier drained without a result");
    }
    rounds += 1;
    fsum += f;
    if (f > fmax) { fmax = f; }
    if (f == 1) { h1 += 1; } else if (f <= 128) { h128 += 1; } else if (f <= 1024) { h1k += 1; }
    else if (f <= 16384) { h16k += 1; } else { hbig += 1; }
    if (gpu) {
      gpu_pass(f);
    } else {"""
assert s.count(old) == 1, "cube_run not found; runtime changed?"
s = s.replace(old, new)
open(p, "w").write(s)
PY
clang -DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules -std=c11 -O3 "$OUT/$NAME.c" -lpthread -lm -o "$OUT/$NAME"
"$OUT/$NAME" --gpu-build
echo "built $OUT/$NAME"
