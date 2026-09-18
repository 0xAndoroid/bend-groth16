# IO probe: read a binary file of little-endian U32 words (path from env FILE)
# with File.read_bytes in CHUNK-byte reads, pack the byte list into an
# Array<U32> of 2^N slots, and print the wrapping sum of all words + timings.
# Facts probed: no argv (a compiled binary rejects positional args), no stdin
# effect (open /dev/stdin as a file), File.read_bytes answers a List<U32> of
# bytes (one cons cell per byte) and may return fewer bytes than asked.
# Build: bend io.bend -o io ; FILE=pk.bin N=21 ./io
import Base

type Acc is Type:
  Acc{a: Array<U32>, +i: U32, +w: U32, +k: U32, +s: U32}

type Rd is Type:
  Rd{f: File, st: Acc, +more: Bool}

def pack.fin(full: Bool, a: Array<U32>, +i: U32, +w: U32, +k: U32, +s: U32) -> Acc:
  match full:
    case True{}:
      Acc{a[i] <- w, (i + 1 : U32), 0, 0, (s + w : U32)}
    case False{}:
      Acc{a, i, w, (k + 1 : U32), s}

def pack.step(+b: U32, st: Acc) -> Acc:
  Acc{a, i, w, k, s} = st
  pack.fin(U32.is_eq(k, 3), a, i, (w .|. (b << U32.to_nat((k * 8 : U32))) : U32), k, s)

# one byte per list cell, little-endian into the current word
def pack(bs: List<&2, U32>, st: Acc) -> Acc:
  match bs:
    case Nil{}:
      st
    case Con{b, t}:
      pack(t, pack.step(b, st))

def read.bytes(f: File, st: Acc, bs: List<&2, U32>) -> Rd:
  match bs:
    case Nil{}:
      Rd{f, st, False{}}
    case Con{b, t}:
      Rd{f, pack(b <> t, st), True{}}

def read.res(f: File, st: Acc, r: Result<&1, &1, U32 & String, List<&2, U32>>) -> Rd:
  match r:
    case Done{bs}:
      read.bytes(f, st, bs)
    case Fail{e}:
      Rd{f, st, False{}}

def read.step(st: Acc, rd: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> Rd:
  (f, r) = rd
  read.res(f, st, r)

# fuel-bounded read loop: stop at the first empty read
def read_all(fuel: Nat, +chunk: U32, r: Rd) -> IO(Rd):
  match fuel:
    case 0n:
      IO.pure(Rd, r)
    case 1n+p:
      Rd{f, st, more} = r
      match more:
        case False{}:
          IO.pure(Rd, Rd{f, st, False{}})
        case True{}:
          do IO<Rd>:
            rd : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, chunk)
            out : Rd <- read_all(p, chunk, read.step(st, rd))
            return out

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

def finish(t0: Nat, r: Rd) -> IO(Unit):
  Rd{f, st, more} = r
  Acc{a, i, w, k, s} = st
  do IO<Unit>:
    t1 : Nat <- IO.now()
    File.close(f)
    IO.print("words=" ++ U32.show(i) ++ " sum32=" ++ U32.show(s) ++ " read+pack ms=" ++ Nat.show(Nat.sub(t1, t0)))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("FILE"))
    +n : Nat <- env_nat("N", 21n)
    +chunk : Nat <- env_nat("CHUNK", Nat.pow(2n, 20n))
    t0 : Nat <- IO.now()
    f : File <- IO.try(File, File.open(path, "r"))
    r : Rd <- read_all(Nat.pow(2n, 17n), U32.from_nat(chunk), Rd{f, Acc{Array.new(U32, n, 0), 0, 0, 0, 0}, True{}})
    finish(t0, r)
