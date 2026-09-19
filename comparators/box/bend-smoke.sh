#!/bin/bash
export PATH=$HOME/.bend/bin:$HOME/.bun/bin:/usr/local/cuda/bin:$PATH; export BEND_NO_TELEMETRY=1
# Bend 2 smoke test on the box: interpreter run, native C build (clang), GPU `!` build (needs clang-19: curl -fsSL https://apt.llvm.org/llvm.sh | bash -s 19).
set -x
bend --version; bend --help 2>&1 | head -40
T=${T:-${TMPDIR:-/tmp}/bendtest}; mkdir -p "$T" && cd "$T"
cat > hello.bend <<'B'
import Base
def main() -> IO(Unit):
  IO.print("hello from bend")
B
cat > pow2.bend <<'B'
import Base
def pow2(+d: Nat) -> U32:
  match d:
    case 0n:
      1
    case 1n+p:
      a b = pow2(p) pow2(p)
      (a + b : U32)
def main() -> IO(Unit):
  result = pow2!(20n)
  IO.print(U32.show(result))
B
clang --version | head -1; nvcc --version | tail -1
time bend hello.bend
time bend pow2.bend
ls -la

bend hello.bend -o hello && ./hello && bend hello.bend -o hello.c && wc -l hello.c
bend pow2.bend -o pow2 && ./pow2 && ldd ./pow2 | grep -iE 'cuda|nvrtc'
