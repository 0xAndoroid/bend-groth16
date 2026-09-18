# Binary input: read a little-endian .bin of U32 words (bend2/FORMAT.md) into an
# Array<U32> of 2^d slots, file word w landing at index pad + w. `pad` lets a file
# with a u32 count header keep its 16-word field elements 16-aligned (pad = 15).
# Adapted from bend2/probe/io.bend: File.read_bytes yields a List of bytes, possibly
# fewer than asked, so loop until an empty read.
import Base

type Acc is Type:
  Acc{a: Array<U32>, +i: U32, +w: U32, +k: U32}

type Rd is Type:
  Rd{f: File, st: Acc, +more: Bool}

def pack.fin(full: Bool, a: Array<U32>, +i: U32, +w: U32, +k: U32) -> Acc:
  match full:
    case True{}:
      Acc{a[i] <- w, (i + 1 : U32), 0, 0}
    case False{}:
      Acc{a, i, w, (k + 1 : U32)}

def pack.step(+b: U32, st: Acc) -> Acc:
  Acc{a, i, w, k} = st
  pack.fin(U32.is_eq(k, 3), a, i, (w .|. (b << U32.to_nat((k * 8 : U32))) : U32), k)

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

def finish(r: Rd) -> IO(Array<U32>):
  Rd{f, st, more} = r
  Acc{a, i, w, k} = st
  do IO<Array<U32>>:
    File.close(f)
    return a

# read `path` into 2^d U32 slots (zero-filled), file word w at index pad + w
def load_u32(path: String, d: Nat, +pad: U32) -> IO(Array<U32>):
  do IO<Array<U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : Rd <- read_all(Nat.pow(2n, 17n), U32.from_nat(Nat.pow(2n, 20n)), Rd{f, Acc{Array.new(U32, d, 0), pad, 0, 0}, True{}})
    a : Array<U32> <- finish(r)
    return a
