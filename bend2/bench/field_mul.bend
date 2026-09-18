# Batch of 2^N independent Fr Montgomery products as a balanced fork tree of depth FD
# (leaf = 2^(N-FD) sequential products on hash-generated inputs, xor-folded on limb 0).
# MODE=cpu runs tree(...) on the CPU (--threads N), MODE=gpu runs tree!(...) on Metal/CUDA.
# Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend field_mul.bend -o field_mul
# Run:   MODE=cpu N=24 FD=14 ./field_mul --threads 10 ; MODE=gpu N=24 FD=16 ./field_mul
import Base
import ../src/fr.bend as F

def h(+i: U32) -> U32:
  (((i * 2654435761) .^. (i >> 15n)) * 2246822519 : U32)

# pseudo-random element below p: 16-bit limbs from h, top limb masked to 0x2FFF
def rnd(+s: U32) -> F.Fr:
  F.Fr{(h(s) .&. 65535 : U32), (h((s + 40504 : U32)) .&. 65535 : U32), (h((s + 81007 : U32)) .&. 65535 : U32), (h((s + 121510 : U32)) .&. 65535 : U32), (h((s + 162013 : U32)) .&. 65535 : U32), (h((s + 202516 : U32)) .&. 65535 : U32), (h((s + 243019 : U32)) .&. 65535 : U32), (h((s + 283522 : U32)) .&. 65535 : U32), (h((s + 324025 : U32)) .&. 65535 : U32), (h((s + 364528 : U32)) .&. 65535 : U32), (h((s + 405031 : U32)) .&. 65535 : U32), (h((s + 445534 : U32)) .&. 65535 : U32), (h((s + 486037 : U32)) .&. 65535 : U32), (h((s + 526540 : U32)) .&. 65535 : U32), (h((s + 567043 : U32)) .&. 65535 : U32), (h((s + 607546 : U32)) .&. 12287 : U32)}

# sequential leaf: n products on distinct inputs
def leaf(n: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      leaf(p, (i + 1 : U32), (acc .^. F.Fr.lo(F.Fr.mul(rnd((i * 2 : U32)), rnd((i * 2 + 1 : U32)))) : U32))

# balanced fork tree: d levels, each leaf runs ln products over its own index range
def tree(d: Nat, +ln: Nat, +i: U32, +w: U32) -> U32:
  match d:
    case 0n:
      leaf(ln, i, 0)
    case 1n++p:
      +hw = (w >> 1n : U32)
      a b = tree(p, ln, i, hw) tree(p, ln, (i + hw : U32), hw)
      (a .^. b : U32)

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

def env_str.fin(r: Result<&1, &1, U32 & String, String>, dflt: String) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      dflt

def env_str(name: String, dflt: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env_str.fin(r, dflt)

def run(g: Bool, +n: Nat, +fd: Nat) -> U32:
  match g:
    case True{}:
      tree!(fd, Nat.pow(2n, Nat.sub(n, fd)), 0, U32.from_nat(Nat.pow(2n, n)))
    case False{}:
      tree(fd, Nat.pow(2n, Nat.sub(n, fd)), 0, U32.from_nat(Nat.pow(2n, n)))

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- env_str("MODE", "cpu")
    +n : Nat <- env_nat("N", 20n)
    +fd : Nat <- env_nat("FD", 14n)
    t0 : Nat <- IO.now()
    +x : U32 = run(String.eq(mode, "gpu"), n, fd)
    t1 : Nat <- IO.now()
    IO.print("field_mul " ++ mode ++ " N=" ++ Nat.show(n) ++ " FD=" ++ Nat.show(fd) ++ " xor=" ++ U32.show(x) ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))
