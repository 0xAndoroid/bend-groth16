# Array probe: Array<U32> of 2^N slots (N from env, default 20): fill in place in
# a loop, gather through an index array, sum. Prints per-phase ms.
# Idiom: a read a[i] answers (array, value); that pair (and any record) can only
# be opened at the top of a def that receives it as a PARAMETER, so every read
# flows into a small non-recursive "stage" def and the loop recurses on the
# stage's result; a def must be declared before its first use (see bench/runtime/bfs/main.bend in bendlang/bend).
# Build: bend arrays.bend -o arrays ; N=24 ./arrays
import Base

type G is Type:
  G{src: Array<U32>, idx: Array<U32>, out: Array<U32>}

def h(+i: U32) -> U32:
  (((i * 2654435761) .^. (i >> 15n)) * 2246822519 : U32)

# a[i] <- h(i) for i in [0, n)
def fill(n: Nat, +i: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- h(i)
      fill(p, (i + 1 : U32), a)

def fill_idx(n: Nat, +i: U32, +mask: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      a[i] <- (h((i + 77 : U32)) .&. mask : U32)
      fill_idx(p, (i + 1 : U32), mask, a)

# out[i] <- src[idx[i]] : three stages, one per pair to open
def gather.put(+i: U32, idx: Array<U32>, out: Array<U32>, r: Array<U32> & U32) -> G:
  (src, v) = r
  G{src, idx, out[i] <- v}

def gather.read(+i: U32, src: Array<U32>, out: Array<U32>, r: Array<U32> & U32) -> G:
  (idx, +j) = r
  gather.put(i, idx, out, src[j])

def gather.step(+i: U32, st: G) -> G:
  G{src, idx, out} = st
  gather.read(i, src, out, idx[i])

def gather(n: Nat, +i: U32, st: G) -> G:
  match n:
    case 0n:
      st
    case 1n+p:
      gather(p, (i + 1 : U32), gather.step(i, st))

def total.step(acc: U32, r: Array<U32> & U32) -> Array<U32> & U32:
  (a, v) = r
  (a, (acc + v : U32))

def total(n: Nat, +i: U32, st: Array<U32> & U32) -> Array<U32> & U32:
  match n:
    case 0n:
      st
    case 1n+p:
      (a, acc) = st
      total(p, (i + 1 : U32), total.step(acc, a[i]))

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

def report(label: String, t0: Nat, t1: Nat) -> IO(Unit):
  IO.print(label ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))

def show_sums(r1: Array<U32> & U32, r2: Array<U32> & U32) -> IO(Unit):
  (o, s1) = r1
  (a, s2) = r2
  IO.print("gather_sum=" ++ U32.show(s1) ++ " fill_sum=" ++ U32.show(s2))

def sums(+cnt: Nat, st: G) -> IO(Unit):
  G{src, idx, out} = st
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    r1 : Array<U32> & U32 = total(cnt, 0, (out, 0))
    +t1 : Nat <- IO.now()
    r2 : Array<U32> & U32 = total(cnt, 0, (src, 0))
    +t2 : Nat <- IO.now()
    show_sums(r1, r2)
    report("sum(out)", t0, t1)
    report("sum(src)", t1, t2)

def main() -> IO(Unit):
  do IO<Unit>:
    +n : Nat <- env_nat("N", 20n)
    +cnt : Nat = Nat.pow(2n, n)
    +mask : U32 = (U32.from_nat(cnt) - 1 : U32)
    IO.print("N=" ++ Nat.show(n))
    +t0 : Nat <- IO.now()
    a : Array<U32> = Array.new(U32, n, 0)
    +t1 : Nat <- IO.now()
    a2 : Array<U32> = fill(cnt, 0, a)
    +t2 : Nat <- IO.now()
    idx : Array<U32> = fill_idx(cnt, 0, mask, Array.new(U32, n, 0))
    +t3 : Nat <- IO.now()
    g : G = gather(cnt, 0, G{a2, idx, Array.new(U32, n, 0)})
    +t4 : Nat <- IO.now()
    report("new", t0, t1)
    report("fill(in-place loop)", t1, t2)
    report("fill_idx", t2, t3)
    report("gather", t3, t4)
    sums(cnt, g)
