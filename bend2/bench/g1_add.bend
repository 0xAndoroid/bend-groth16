# 2^N G1 mixed additions (Jacobian + affine, the MSM hot op) as a balanced fork tree of
# depth FD; each leaf accumulates a chain acc <- acc + G of 2^(N-FD) adds starting from G
# (first step hits the P == Q doubling path, the rest the generic madd-2007-bl path).
# Checksum = wrapping sum over leaves of limb 0 of the Jacobian X coordinate.
# Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend g1_add.bend -o g1_add
# Run:   MODE=cpu N=20 FD=14 ./g1_add --threads 10 ; MODE=gpu N=20 FD=14 ./g1_add
import Base
import ../src/fq.bend as Q
import ../src/g1.bend as G

# BN254 G1 generator (1, 2) in Montgomery form
def gen() -> G.G1Aff:
  G.G1Aff{Q.Fq.one(), Q.Fq.add(Q.Fq.one(), Q.Fq.one())}

def xlo(p: G.G1) -> U32:
  match p:
    case G.G1{x, y, z}:
      Q.Fq.lo(x)

def leaf(n: Nat, acc: G.G1, +q: G.G1Aff) -> G.G1:
  match n:
    case 0n:
      acc
    case 1n+p:
      leaf(p, G.G1.add_mixed(acc, q), q)

def tree(d: Nat, +ln: Nat) -> U32:
  match d:
    case 0n:
      xlo(leaf(ln, G.G1.from_affine(gen()), gen()))
    case 1n++p:
      a b = tree(p, ln) tree(p, ln)
      (a + b : U32)

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
      tree!(fd, Nat.pow(2n, Nat.sub(n, fd)))
    case False{}:
      tree(fd, Nat.pow(2n, Nat.sub(n, fd)))

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- env_str("MODE", "cpu")
    +n : Nat <- env_nat("N", 20n)
    +fd : Nat <- env_nat("FD", 14n)
    t0 : Nat <- IO.now()
    +x : U32 = run(String.eq(mode, "gpu"), n, fd)
    t1 : Nat <- IO.now()
    IO.print("g1_add " ++ mode ++ " N=" ++ Nat.show(n) ++ " FD=" ++ Nat.show(fd) ++ " sum=" ++ U32.show(x) ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))
