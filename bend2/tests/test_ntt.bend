# NTT checks. Vectors mode (default): data/vectors/bend/ntt_small_{8,64,1024}.bin, per size
# fft(coeffs) == evals, ifft(evals) == coeffs, ifft(fft(coeffs)) == coeffs, and
# coset_ifft(coset_fft(coeffs)) == coeffs; prints "PASS <n>" per size, or exits 1 with "FAIL ...".
# QAP mode (K=<k> in the env): loads data/<K>/bend/{header,abc_evals,h_ref}.bin (written by
# `uv run python bend2/gen/ref_qap.py data/<K>`), runs Ntt.qap_h and compares with h_ref.
# Run from the repo root: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend bend2/tests/test_ntt.bend -o t && ./t && K=4 ./t
import Base
import ../src/fr.bend as R
import ../src/ntt.bend as Ntt
import ../src/bin_io.bend as Io

# ---- copy n elements: dst[i] = src[u0 + i] ----

type Cp is Type:
  Cp{src: Array<U32>, dst: Array<U32>}

def T.copy.s0(+i: Nat, dst: Array<U32>, pr: Array<U32> & R.Fr) -> Cp:
  (src, x) = pr
  Cp{src, R.Fr.to_array(dst, i, x)}

def T.copy(n: Nat, +i: Nat, +u0: Nat, st: Cp) -> Cp:
  match n:
    case 0n:
      st
    case 1n++p:
      Cp{src, dst} = st
      T.copy(p, (i + 1n), u0, T.copy.s0(i, dst, R.Fr.from_array(src, (u0 + i))))

# ---- count mismatches: a[i] != arr[u0 + i] ----

type Cm is Type:
  Cm{a: Array<U32>, arr: Array<U32>, +bad: U32}

def T.cmp.s1(+bad: U32, a: Array<U32>, +x: R.Fr, pr: Array<U32> & R.Fr) -> Cm:
  (arr, y) = pr
  Cm{a, arr, U32.add(bad, U32.sub(1, R.Fr.eq(x, y)))}

def T.cmp.s0(+i: Nat, +u0: Nat, +bad: U32, arr: Array<U32>, pr: Array<U32> & R.Fr) -> Cm:
  (a, x) = pr
  T.cmp.s1(bad, a, x, R.Fr.from_array(arr, (u0 + i)))

def T.cmp(n: Nat, +i: Nat, +u0: Nat, st: Cm) -> Cm:
  match n:
    case 0n:
      st
    case 1n++p:
      Cm{a, arr, bad} = st
      T.cmp(p, (i + 1n), u0, T.cmp.s0(i, u0, bad, arr, R.Fr.from_array(a, i)))

def T.cmp.bad(st: Cm) -> U32:
  Cm{a, arr, bad} = st
  bad

# ---- vectors mode ----

# fresh 2^(log2+4)-word array holding arr[u0 .. u0+n)
def T.extract(arr: Array<U32>, +log2: Nat, +u0: Nat) -> Cp:
  T.copy(Nat.pow(2n, log2), 0n, u0, Cp{arr, Array.new(U32, (log2 + 4n), 0)})

# file layout in 16-word units (pad 15): count | omega | n_inv | coeffs (n) | evals (n) | icoeffs (n)
def T.vec.report(ok: Bool, +n: Nat, +b1: U32, +b2: U32, +b3: U32, +b4: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ Nat.show(n))
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ Nat.show(n) ++ " fft=" ++ U32.show(b1) ++ " ifft=" ++ U32.show(b2) ++ " ifft.fft=" ++ U32.show(b3) ++ " coset_ifft.coset_fft=" ++ U32.show(b4))

def T.vec.step4(+log2: Nat, +n: Nat, +b1: U32, +b2: U32, +b3: U32, st: Cm) -> IO(Unit):
  Cm{a, arr, b4} = st
  T.vec.report(U32.is_eq(U32.or(U32.or(b1, b2), U32.or(b3, b4)), 0), n, b1, b2, b3, b4)

# coset_ifft(coset_fft(coeffs)) == coeffs
def T.vec.step3.go(+log2: Nat, +n: Nat, +b1: U32, +b2: U32, +b3: U32, c: Cp) -> IO(Unit):
  Cp{arr, x} = c
  T.vec.step4(log2, n, b1, b2, b3, T.cmp(n, 0n, 3n, Cm{Ntt.Ntt.coset_ifft(Ntt.Ntt.coset_fft(x, log2), log2), arr, 0}))

def T.vec.step3(+log2: Nat, +n: Nat, +b1: U32, +b2: U32, st: Cm) -> IO(Unit):
  Cm{a, arr, b3} = st
  T.vec.step3.go(log2, n, b1, b2, b3, T.extract(arr, log2, 3n))

# ifft(fft(coeffs)) == coeffs
def T.vec.step2.go(+log2: Nat, +n: Nat, +b1: U32, +b2: U32, c: Cp) -> IO(Unit):
  Cp{arr, x} = c
  T.vec.step3(log2, n, b1, b2, T.cmp(n, 0n, 3n, Cm{Ntt.Ntt.ifft(Ntt.Ntt.fft(x, log2), log2), arr, 0}))

def T.vec.step2(+log2: Nat, +n: Nat, +b1: U32, st: Cm) -> IO(Unit):
  Cm{a, arr, b2} = st
  T.vec.step2.go(log2, n, b1, b2, T.extract(arr, log2, 3n))

# ifft(evals) == coeffs
def T.vec.step1.go(+log2: Nat, +n: Nat, +b1: U32, c: Cp) -> IO(Unit):
  Cp{arr, x} = c
  T.vec.step2(log2, n, b1, T.cmp(n, 0n, 3n, Cm{Ntt.Ntt.ifft(x, log2), arr, 0}))

def T.vec.step1(+log2: Nat, +n: Nat, st: Cm) -> IO(Unit):
  Cm{a, arr, b1} = st
  T.vec.step1.go(log2, n, b1, T.extract(arr, log2, (3n + n)))

# fft(coeffs) == evals
def T.vec.step0(+log2: Nat, +n: Nat, c: Cp) -> IO(Unit):
  Cp{arr, x} = c
  T.vec.step1(log2, n, T.cmp(n, 0n, (3n + n), Cm{Ntt.Ntt.fft(x, log2), arr, 0}))

def T.vec.cnt.go(ok: Bool, path: String, +log2: Nat, +c: U32, arr: Array<U32>) -> IO(Unit):
  match ok:
    case True{}:
      T.vec.step0(log2, Nat.pow(2n, log2), T.extract(arr, log2, 3n))
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ path ++ " count=" ++ U32.show(c))

def T.vec.cnt(path: String, +log2: Nat, pr: Array<U32> & U32) -> IO(Unit):
  (arr, +c) = pr
  T.vec.cnt.go(U32.is_eq(c, U32.from_nat(Nat.pow(2n, log2))), path, log2, c, arr)

def T.vec(+path: String, +log2: Nat) -> IO(Unit):
  do IO<Unit>:
    arr : Array<U32> <- Io.load_u32(path, (log2 + 6n), 15)
    T.vec.cnt(path, log2, arr[15])

# ---- QAP mode ----

def T.env.fin(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def T.hdr.s0(pr: Array<U32> & U32) -> Nat:
  (a, +w) = pr
  U32.to_nat(w)

# abc_evals.bin = a | b | c (d elements each), loaded into 4d elements: halves (a|b), (c|0)
def T.qap.split(t: Array<U32>) -> Array<U32> & (Array<U32> & Array<U32>):
  match t:
    case ALeaf{x}:
      (ALeaf{x}, (ALeaf{0}, ALeaf{0}))
    case ANode{ab, c0}:
      match ab c0:
        case ANode{a, b} ANode{c, z}:
          (a, (b, c))
        case ANode{a, b} ALeaf{y}:
          (a, (b, ALeaf{y}))
        case ALeaf{x} ANode{c, z}:
          (ALeaf{x}, (c, z))
        case ALeaf{x} ALeaf{y}:
          (ALeaf{x}, (ALeaf{y}, ALeaf{0}))

def T.qap.run3(+log2: Nat, a: Array<U32>, href: Array<U32>, bc: Array<U32> & Array<U32>) -> U32:
  (b, c) = bc
  T.cmp.bad(T.cmp(Nat.pow(2n, log2), 0n, 0n, Cm{Ntt.Ntt.qap_h(a, b, c, log2), href, 0}))

def T.qap.run2(+log2: Nat, href: Array<U32>, pr: Array<U32> & (Array<U32> & Array<U32>)) -> U32:
  (a, bc) = pr
  T.qap.run3(log2, a, href, bc)

def T.qap.report.go(ok: Bool, +log2: Nat, +bad: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS qap_h d=2^" ++ Nat.show(log2))
    case False{}:
      IO.die(Unit, 1, "FAIL qap_h d=2^" ++ Nat.show(log2) ++ " bad=" ++ U32.show(bad))

def T.qap.report(+log2: Nat, +bad: U32) -> IO(Unit):
  T.qap.report.go(U32.is_eq(bad, 0), log2, bad)

def T.qap.go(+dir: String, +log2: Nat) -> IO(Unit):
  do IO<Unit>:
    abc : Array<U32> <- Io.load_u32(dir ++ "/bend/abc_evals.bin", (log2 + 6n), 0)
    href : Array<U32> <- Io.load_u32(dir ++ "/bend/h_ref.bin", (log2 + 4n), 0)
    T.qap.report(log2, T.qap.run2(log2, href, T.qap.split(abc)))

def T.qap(+k: String) -> IO(Unit):
  +dir = "data/" ++ k
  do IO<Unit>:
    hdr : Array<U32> <- Io.load_u32(dir ++ "/bend/header.bin", 4n, 0)
    T.qap.go(dir, T.hdr.s0(hdr[3]))

def T.main(k: Maybe<&2, String>) -> IO(Unit):
  match k:
    case Some{s}:
      T.qap(s)
    case None{}:
      do IO<Unit>:
        T.vec("data/vectors/bend/ntt_small_8.bin", 3n)
        T.vec("data/vectors/bend/ntt_small_64.bin", 6n)
        T.vec("data/vectors/bend/ntt_small_1024.bin", 10n)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("K")
    T.main(T.env.fin(r))
