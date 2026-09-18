# Parallel-reduce probe: sum of h(i) over 2^N elements.
#   MODE=seq   sequential Nat-fuel loop
#   MODE=par   fork/join tree (depth FD) with sequential leaves, on CPU
#   MODE=gpu   same tree via par!(..): Metal when --gpu on (default), CPU when --gpu off
# Env: N (log2 elements, default 24), FD (fork depth, default 14), K (hash rounds per element, default 4).
# Build: bend parallel.bend -o parallel ; MODE=par ./parallel --threads 1
import Base

def h(+i: U32) -> U32:
  (((i * 2654435761) .^. (i >> 15n)) * 2246822519 : U32)

# K chained hash rounds per element: a serial dependency chain, so clang cannot
# vectorize it away and the time measures real per-element work
def rounds(k: Nat, x: U32) -> U32:
  match k:
    case 0n:
      x
    case 1n+p:
      rounds(p, h(x))

def seq(n: Nat, +k: Nat, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      seq(p, k, (i + 1 : U32), rounds(k, (acc .^. i : U32)))

# d: fork levels left; ln: leaf length as Nat; i: first index; w: width of this subtree
def par(d: Nat, +ln: Nat, +k: Nat, +i: U32, +w: U32) -> U32:
  match d:
    case 0n:
      seq(ln, k, i, 0)
    case 1n++p:
      +hw = (w >> 1n : U32)
      a b = par(p, ln, k, i, hw) par(p, ln, k, (i + hw : U32), hw)
      (a + b : U32)

# env helpers: a match must head a def body and inspect a parameter, so each
# decision is its own def
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

def run.gpu(g: Bool, +n: Nat, +fd: Nat, +k: Nat) -> U32:
  match g:
    case True{}:
      par!(fd, Nat.pow(2n, Nat.sub(n, fd)), k, 0, U32.from_nat(Nat.pow(2n, n)))
    case False{}:
      par(fd, Nat.pow(2n, Nat.sub(n, fd)), k, 0, U32.from_nat(Nat.pow(2n, n)))

def run(s: Bool, g: Bool, +n: Nat, +fd: Nat, +k: Nat) -> U32:
  match s:
    case True{}:
      seq(Nat.pow(2n, n), k, 0, 0)
    case False{}:
      run.gpu(g, n, fd, k)

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- IO.try(String, IO.get_env("MODE"))
    +n : Nat <- env_nat("N", 24n)
    +fd : Nat <- env_nat("FD", 14n)
    +k : Nat <- env_nat("K", 4n)
    t0 : Nat <- IO.now()
    s : U32 = run(String.eq(mode, "seq"), String.eq(mode, "gpu"), n, fd, k)
    t1 : Nat <- IO.now()
    IO.print(mode ++ " N=" ++ Nat.show(n) ++ " FD=" ++ Nat.show(fd) ++ " K=" ++ Nat.show(k) ++ " sum=" ++ U32.show(s) ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))
