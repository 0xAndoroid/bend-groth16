# NTT benchmark on pseudo-random Fr data (hash-generated, not timed).
# Env: OP=fft|ifft|coset_fft|qap_h (0|1|2|3), N=<log2 size> (qap_h: N = domain log2),
#      FD=<fork depth, 2^FD chunks; default Ntt.fd(N)>, MODE=cpu|gpu (gpu = the `!` call on Metal/CUDA).
# Prints "ntt <op> <mode> N=.. FD=.. sum=<checksum> ms=<wall>"; the checksum is the U32 sum of
# limb 0 of every output element and must agree across threads/modes.
# Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend ntt.bend -o ntt
# Run:   OP=0 N=20 ./ntt --threads 1 ; OP=0 N=20 ./ntt ; MODE=gpu OP=0 N=20 FD=12 ./ntt
import Base
import ../src/fr.bend as F
import ../src/ntt.bend as Ntt

def h(+i: U32) -> U32:
  (((i * 2654435761) .^. (i >> 15n)) * 2246822519 : U32)

# word i of a random element array: 16-bit limbs, limb 15 masked to 0x2FFF so the value is < p
def word(+i: U32, +seed: U32) -> U32:
  (h((i .^. seed : U32)) .&. (65535 - (Bool.to_u32(U32.is_eq((i .&. 15 : U32), 15)) * 53248 : U32) : U32) : U32)

def fill(n: Nat, +i: U32, +seed: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      fill(p, (i + 1 : U32), seed, a[i] <- word(i, seed))

def rnd(+log2: Nat, +seed: U32) -> Array<U32>:
  fill(Nat.pow(2n, (log2 + 4n)), 0, seed, Array.new(U32, (log2 + 4n), 0))

# checksum: sum of word 16 i (limb 0) over all elements
def sum.go(n: Nat, +i: U32, +acc: U32, r: Array<U32> & U32) -> U32:
  match n:
    case 0n:
      (a, +v) = r
      (acc + v : U32)
    case 1n+p:
      (a, +v) = r
      sum.go(p, (i + 16 : U32), (acc + v : U32), a[i])

def sum(log2: Nat, a: Array<U32>) -> U32:
  sum.go(Nat.sub(Nat.pow(2n, log2), 1n), 16, 0, a[0])

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

def opname(op: Nat) -> String:
  match op:
    case 0n:
      "fft"
    case 1n+p:
      match p:
        case 0n:
          "ifft"
        case 1n+q:
          match q:
            case 0n:
              "coset_fft"
            case 1n+r:
              "qap_h"

def run_cpu(op: Nat, a: Array<U32>, b: Array<U32>, c: Array<U32>, +n: Nat, +fd: Nat) -> Array<U32>:
  match op:
    case 0n:
      Ntt.Ntt.fft_fd(a, n, fd)
    case 1n+p:
      match p:
        case 0n:
          Ntt.Ntt.ifft_fd(a, n, fd)
        case 1n+q:
          match q:
            case 0n:
              Ntt.Ntt.coset_fft_fd(a, n, fd)
            case 1n+r:
              Ntt.Ntt.qap_h_fd(a, b, c, n, fd)

def run_gpu(op: Nat, a: Array<U32>, b: Array<U32>, c: Array<U32>, +n: Nat, +fd: Nat) -> Array<U32>:
  match op:
    case 0n:
      Ntt.Ntt.fft_fd!(a, n, fd)
    case 1n+p:
      match p:
        case 0n:
          Ntt.Ntt.ifft_fd!(a, n, fd)
        case 1n+q:
          match q:
            case 0n:
              Ntt.Ntt.coset_fft_fd!(a, n, fd)
            case 1n+r:
              Ntt.Ntt.qap_h_fd!(a, b, c, n, fd)

def run(gpu: Bool, op: Nat, a: Array<U32>, b: Array<U32>, c: Array<U32>, +n: Nat, +fd: Nat) -> Array<U32>:
  match gpu:
    case True{}:
      run_gpu(op, a, b, c, n, fd)
    case False{}:
      run_cpu(op, a, b, c, n, fd)

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- env_str("MODE", "cpu")
    +op : Nat <- env_nat("OP", 0n)
    +n : Nat <- env_nat("N", 20n)
    +fd : Nat <- env_nat("FD", Ntt.Ntt.fd(n))
    a : Array<U32> = rnd(n, 1)
    b : Array<U32> = rnd(n, 2)
    c : Array<U32> = rnd(n, 3)
    +t0 : Nat <- IO.now()
    +s : U32 = sum(n, run(String.eq(mode, "gpu"), op, a, b, c, n, fd))
    +t1 : Nat <- IO.now()
    IO.print("ntt " ++ opname(op) ++ " " ++ mode ++ " N=" ++ Nat.show(n) ++ " FD=" ++ Nat.show(fd) ++ " sum=" ++ U32.show(s) ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)))
