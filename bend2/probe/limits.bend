# Limits probe: non-tail recursion depth (a 2^D-cell list built without an
# accumulator), then Array.new at 2^A slots (A from env, default 27 = 512 MB).
# Build: bend limits.bend -o limits ; D=24 A=30 ./limits
import Base

def build(n: Nat) -> List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      1 <> build(p)

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

def size_of(r: Array<U32> & U32) -> U32:
  (a, n) = r
  n

def main() -> IO(Unit):
  do IO<Unit>:
    +d : Nat <- env_nat("D", 20n)
    +a : Nat <- env_nat("A", 27n)
    t0 : Nat <- IO.now()
    +len : Nat = List.length(&1, U32, build(Nat.pow(2n, d)))
    +t1 : Nat <- IO.now()
    IO.print("list 2^" ++ Nat.show(d) ++ " non-tail build: len=" ++ Nat.show(len) ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))
    +sz : U32 = size_of(Array.size(U32, Array.new(U32, a, 7)))
    t2 : Nat <- IO.now()
    IO.print("Array.new 2^" ++ Nat.show(a) ++ " size=" ++ U32.show(sz) ++ " ms=" ++ Nat.show(Nat.sub(t2, t1)))
