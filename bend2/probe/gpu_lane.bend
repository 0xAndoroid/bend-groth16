# GPU-lane probe (review lane C, docs/review-notes.md): what one Metal/CUDA lane costs
# against one CPU core, and whether the per-`!` cost is per call or per process.
#   fmul  : 2^N sequential Fr.mul on ONE lane (`!` at fork depth 0) vs one CPU thread
#   walk  : 2^N sequential a[i] <- a[i]+h(i) on ONE lane vs one CPU thread (memory latency)
#   twice : the same 2^N fmul `!` issued twice in one process (second call = steady-state `!` cost)
# Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend gpu_lane.bend -o gpu_lane ; N=18 ./gpu_lane --threads 1
import Base
import ../src/fr.bend as F

def h(+i: U32) -> U32:
  (((i * 2654435761) .^. (i >> 15n)) * 2246822519 : U32)

def rnd(+s: U32) -> F.Fr:
  F.Fr{(h(s) .&. 65535 : U32), (h((s + 40504 : U32)) .&. 65535 : U32), (h((s + 81007 : U32)) .&. 65535 : U32), (h((s + 121510 : U32)) .&. 65535 : U32), (h((s + 162013 : U32)) .&. 65535 : U32), (h((s + 202516 : U32)) .&. 65535 : U32), (h((s + 243019 : U32)) .&. 65535 : U32), (h((s + 283522 : U32)) .&. 65535 : U32), (h((s + 324025 : U32)) .&. 65535 : U32), (h((s + 364528 : U32)) .&. 65535 : U32), (h((s + 405031 : U32)) .&. 65535 : U32), (h((s + 445534 : U32)) .&. 65535 : U32), (h((s + 486037 : U32)) .&. 65535 : U32), (h((s + 526540 : U32)) .&. 65535 : U32), (h((s + 567043 : U32)) .&. 65535 : U32), (h((s + 607546 : U32)) .&. 12287 : U32)}

def leaf(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      leaf(p, (i + 1 : U32), (acc .^. F.Fr.lo(F.Fr.mul(rnd((i * 2 : U32)), rnd((i * 2 + 1 : U32)))) : U32))

def fmul(n: Nat, +i: U32) -> U32:
  leaf(n, i, 0)

def walk.step(+i: U32, r: Array<U32> & U32) -> Array<U32>:
  (a, v) = r
  a[i] <- (v + h(i) : U32)

def walk.go(n: Nat, +i: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      walk.go(p, (i + 1 : U32), walk.step(i, a[i]))

def sum.step(acc: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, v) = r
  (a, (acc + v : U32))

def sum.go(n: Nat, +i: U32, st: Array<U32> & U32) -> Array<U32> & U32:
  match n:
    case 0n:
      st
    case 1n+p:
      (a, acc) = st
      sum.go(p, (i + 1 : U32), sum.step(acc, a[i]))

def sum.fin(st: Array<U32> & U32) -> U32:
  (a, s) = st
  s

def walk(+d: Nat, +n: Nat) -> U32:
  sum.fin(sum.go(n, 0, (walk.go(n, 0, Array.new(U32, d, 7)), 0)))

def env_nat.parse(m: Maybe<&2, U32>, +dflt: Nat) -> Nat:
  match m:
    case Some{v}:
      U32.to_nat(v)
    case None{}:
      dflt

def env_nat.fin(r: Result<&1, &1, U32 & String, String>, +dflt: Nat) -> Nat:
  match r:
    case Done{s}:
      env_nat.parse(U32.read(s), dflt)
    case Fail{e}:
      dflt

def env_nat(name: String, +dflt: Nat) -> IO(Nat):
  do IO<Nat>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env_nat.fin(r, dflt)

def main() -> IO(Unit):
  do IO<Unit>:
    +d : Nat <- env_nat("N", 18n)
    +n : Nat = Nat.pow(2n, d)
    t0 : Nat <- IO.now()
    +x1 : U32 = fmul!(n, 0)
    +t1 : Nat <- IO.now()
    +x2 : U32 = fmul!(n, 1)
    +t2 : Nat <- IO.now()
    +x3 : U32 = fmul(n, 0)
    +t3 : Nat <- IO.now()
    +w1 : U32 = walk!(d, n)
    +t4 : Nat <- IO.now()
    +w2 : U32 = walk(d, n)
    t5 : Nat <- IO.now()
    IO.print("gpu_lane N=" ++ Nat.show(d) ++ " fmul_gpu1=" ++ Nat.show(Nat.sub(t1, t0)) ++ " fmul_gpu2=" ++ Nat.show(Nat.sub(t2, t1)) ++ " fmul_cpu=" ++ Nat.show(Nat.sub(t3, t2)) ++ " walk_gpu=" ++ Nat.show(Nat.sub(t4, t3)) ++ " walk_cpu=" ++ Nat.show(Nat.sub(t5, t4)) ++ " x=" ++ U32.show(x1) ++ "/" ++ U32.show(x2) ++ "/" ++ U32.show(x3) ++ " w=" ++ U32.show(w1) ++ "/" ++ U32.show(w2))
