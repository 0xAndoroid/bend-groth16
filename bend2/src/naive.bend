# Naive stand-ins for msm.bend (alias Msm) and ntt.bend (alias Ntt) with the FROZEN wave-2
# interfaces (bend2/README.md): correct and slow, for validating the prover wiring end to end.
# Import this one file twice: `import ./naive.bend as Msm` / `import ./naive.bend as Ntt`.
# MSM: fork tree over index ranges (arrays cloned per fork), leaf = mul_scalar + add.
# NTT: O(n^2) DFT against a twiddle table; qap_h composed exactly like arkworks' libsnark
# reduction (ifft -> coset_fft -> (a*b - c) / (g^d - 1) -> coset_ifft).
import Base
import ./fr.bend as R
import ./g1.bend as G
import ./g2.bend as G2

# ---------------------------------------------------------------- MSM (G1)

def Msm.g1.s1(+p: G.G1Aff, acc: G.G1, r: Array<U32> & R.Fr) -> Array<U32> & G.G1:
  (sc, +k) = r
  (sc, G.G1.add(acc, G.G1.mul_scalar(G.G1.from_affine(p), k)))

def Msm.g1.s0(+i: Nat, acc: G.G1, sc: Array<U32>, r: Array<U32> & G.G1Aff) -> Array<U32> & (Array<U32> & G.G1):
  (pts, +p) = r
  (pts, Msm.g1.s1(p, acc, R.Fr.from_array(sc, i)))

# n terms starting at index i
def Msm.g1.loop(n: Nat, +i: Nat, st: Array<U32> & (Array<U32> & G.G1)) -> Array<U32> & (Array<U32> & G.G1):
  match n:
    case 0n:
      st
    case 1n+m:
      (pts, r) = st
      (sc, acc) = r
      Msm.g1.loop(m, (i + 1n), Msm.g1.s0(i, acc, sc, G.G1Aff.from_array(pts, i)))

def Msm.g1.join(l: Array<U32> & (Array<U32> & G.G1), r: Array<U32> & (Array<U32> & G.G1)) -> Array<U32> & (Array<U32> & G.G1):
  (pl, rl) = l
  (sl, gl) = rl
  (pr, rr) = r
  (sr, gr) = rr
  (pl, (sl, G.G1.add(gl, gr)))

# balanced fork tree over [lo, lo+cnt); each level hands clones of both arrays to its children
def Msm.g1.tree(depth: Nat, +lo: Nat, +cnt: Nat, cp: Array<U32> & Array<U32>, cs: Array<U32> & Array<U32>) -> Array<U32> & (Array<U32> & G.G1):
  match depth:
    case 0n:
      (pts, pts2) = cp
      (sc, sc2) = cs
      Msm.g1.loop(cnt, lo, (pts, (sc, G.G1.infinity())))
    case 1n++d:
      (pts, pts2) = cp
      (sc, sc2) = cs
      +half = (cnt / 2n)
      l r = Msm.g1.tree(d, lo, half, Array.clone(U32, pts), Array.clone(U32, sc)) Msm.g1.tree(d, (lo + half), Nat.sub(cnt, half), Array.clone(U32, pts2), Array.clone(U32, sc2))
      Msm.g1.join(l, r)

# points: n G1 affine (32 words each); scalars: n CANONICAL Fr (16 words each)
def Msm.g1(points: Array<U32>, scalars: Array<U32>, n: Nat) -> Array<U32> & (Array<U32> & G.G1):
  Msm.g1.tree(3n, 0n, n, Array.clone(U32, points), Array.clone(U32, scalars))

# ---------------------------------------------------------------- MSM (G2)

def Msm.g2.s1(+p: G2.G2Aff, acc: G2.G2, r: Array<U32> & R.Fr) -> Array<U32> & G2.G2:
  (sc, +k) = r
  (sc, G2.G2.add(acc, G2.G2.mul_scalar(G2.G2.from_affine(p), k)))

def Msm.g2.s0(+i: Nat, acc: G2.G2, sc: Array<U32>, r: Array<U32> & G2.G2Aff) -> Array<U32> & (Array<U32> & G2.G2):
  (pts, +p) = r
  (pts, Msm.g2.s1(p, acc, R.Fr.from_array(sc, i)))

def Msm.g2.loop(n: Nat, +i: Nat, st: Array<U32> & (Array<U32> & G2.G2)) -> Array<U32> & (Array<U32> & G2.G2):
  match n:
    case 0n:
      st
    case 1n+m:
      (pts, r) = st
      (sc, acc) = r
      Msm.g2.loop(m, (i + 1n), Msm.g2.s0(i, acc, sc, G2.G2Aff.from_array(pts, i)))

def Msm.g2.join(l: Array<U32> & (Array<U32> & G2.G2), r: Array<U32> & (Array<U32> & G2.G2)) -> Array<U32> & (Array<U32> & G2.G2):
  (pl, rl) = l
  (sl, gl) = rl
  (pr, rr) = r
  (sr, gr) = rr
  (pl, (sl, G2.G2.add(gl, gr)))

def Msm.g2.tree(depth: Nat, +lo: Nat, +cnt: Nat, cp: Array<U32> & Array<U32>, cs: Array<U32> & Array<U32>) -> Array<U32> & (Array<U32> & G2.G2):
  match depth:
    case 0n:
      (pts, pts2) = cp
      (sc, sc2) = cs
      Msm.g2.loop(cnt, lo, (pts, (sc, G2.G2.infinity())))
    case 1n++d:
      (pts, pts2) = cp
      (sc, sc2) = cs
      +half = (cnt / 2n)
      l r = Msm.g2.tree(d, lo, half, Array.clone(U32, pts), Array.clone(U32, sc)) Msm.g2.tree(d, (lo + half), Nat.sub(cnt, half), Array.clone(U32, pts2), Array.clone(U32, sc2))
      Msm.g2.join(l, r)

# points: n G2 affine (64 words each); scalars: n CANONICAL Fr
def Msm.g2(points: Array<U32>, scalars: Array<U32>, n: Nat) -> Array<U32> & (Array<U32> & G2.G2):
  Msm.g2.tree(3n, 0n, n, Array.clone(U32, points), Array.clone(U32, scalars))

# ---------------------------------------------------------------- NTT constants

# BN254 Fr TWO_ADIC_ROOT_OF_UNITY (2-adicity 28), Montgomery; bend2/scripts/gen_naive_consts.py
def Ntt.root() -> R.Fr:
  R.Fr{15772, 32977, 29525, 25454, 65494, 9285, 62324, 41515, 984, 7858, 10944, 22085, 63975, 10595, 61332, 6240}

def Ntt.sqr_n(n: Nat, x: R.Fr) -> R.Fr:
  match n:
    case 0n:
      x
    case 1n+m:
      Ntt.sqr_n(m, R.Fr.sqr(x))

# arkworks Radix2EvaluationDomain generator: ROOT^(2^(28 - log2))
def Ntt.omega(log2: Nat) -> R.Fr:
  Ntt.sqr_n(Nat.sub(28n, log2), Ntt.root())

# small integer -> Montgomery Fr
def Ntt.fr_u32(+v: U32) -> R.Fr:
  R.Fr.from_canonical(R.Fr{U32.and(v, 65535), U32.shrn(v, 16n), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})

# Fr::GENERATOR = 5 (the coset offset)
def Ntt.gen() -> R.Fr:
  Ntt.fr_u32(5)

# ---------------------------------------------------------------- O(n^2) DFT

# tw[k] = w^k for k < n
def Ntt.twiddles.loop(n: Nat, +k: Nat, +w: R.Fr, +cur: R.Fr, tw: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      tw
    case 1n+m:
      Ntt.twiddles.loop(m, (k + 1n), w, R.Fr.mul(cur, w), R.Fr.to_array(tw, k, cur))

def Ntt.twiddles(w: R.Fr, +log2: Nat) -> Array<U32>:
  Ntt.twiddles.loop(Nat.pow(2n, log2), 0n, w, R.Fr.one(), Array.new(U32, (log2 + 4n), 0))

def Ntt.dft.s1(acc: R.Fr, x: R.Fr, r: Array<U32> & R.Fr) -> Array<U32> & R.Fr:
  (tw, w) = r
  (tw, R.Fr.add(acc, R.Fr.mul(x, w)))

def Ntt.dft.s0(acc: R.Fr, tw: Array<U32>, +idx: U32, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & R.Fr):
  (a, x) = r
  (a, Ntt.dft.s1(acc, x, R.Fr.from_array(tw, U32.to_nat(idx))))

# out[j] = sum_i a[i] * tw[(i*j) mod n]; idx runs (i*j) mod n by repeated addition of j
def Ntt.dft.inner(n: Nat, +i: Nat, +j: U32, +idx: U32, +mask: U32, st: Array<U32> & (Array<U32> & R.Fr)) -> Array<U32> & (Array<U32> & R.Fr):
  match n:
    case 0n:
      st
    case 1n+m:
      (a, r) = st
      (tw, acc) = r
      Ntt.dft.inner(m, (i + 1n), j, U32.and((idx + j : U32), mask), mask, Ntt.dft.s0(acc, tw, idx, R.Fr.from_array(a, i)))

def Ntt.dft.outer.fin(+j: Nat, out: Array<U32>, st: Array<U32> & (Array<U32> & R.Fr)) -> Array<U32> & (Array<U32> & Array<U32>):
  (a, r) = st
  (tw, v) = r
  (a, (tw, R.Fr.to_array(out, j, v)))

def Ntt.dft.outer(n: Nat, +j: Nat, +cnt: Nat, +mask: U32, st: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & Array<U32>):
  match n:
    case 0n:
      st
    case 1n+m:
      (a, r) = st
      (tw, out) = r
      Ntt.dft.outer(m, (j + 1n), cnt, mask, Ntt.dft.outer.fin(j, out, Ntt.dft.inner(cnt, 0n, U32.from_nat(j), 0, mask, (a, (tw, R.Fr.zero())))))

def Ntt.dft.done(st: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32>:
  (a, r) = st
  (tw, out) = r
  out

# DFT of 2^log2 Montgomery Fr with root w (consumes a, returns a fresh array)
def Ntt.dft(a: Array<U32>, w: R.Fr, +log2: Nat) -> Array<U32>:
  +n = Nat.pow(2n, log2)
  Ntt.dft.done(Ntt.dft.outer(n, 0n, n, U32.from_nat(Nat.sub(n, 1n)), (a, (Ntt.twiddles(w, log2), Array.new(U32, (log2 + 4n), 0)))))

# a[i] *= c
def Ntt.scale.s(+i: Nat, c: R.Fr, r: Array<U32> & R.Fr) -> Array<U32>:
  (a, x) = r
  R.Fr.to_array(a, i, R.Fr.mul(x, c))

def Ntt.scale.loop(n: Nat, +i: Nat, +c: R.Fr, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+m:
      Ntt.scale.loop(m, (i + 1n), c, Ntt.scale.s(i, c, R.Fr.from_array(a, i)))

# a[i] *= g^i (arkworks distribute_powers)
def Ntt.powers.loop(n: Nat, +i: Nat, +g: R.Fr, +cur: R.Fr, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+m:
      Ntt.powers.loop(m, (i + 1n), g, R.Fr.mul(cur, g), Ntt.scale.s(i, cur, R.Fr.from_array(a, i)))

# ---------------------------------------------------------------- frozen NTT interface

def Ntt.fft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.dft(a, Ntt.omega(log2), log2)

def Ntt.ifft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.scale.loop(Nat.pow(2n, log2), 0n, R.Fr.inv(Ntt.fr_u32(U32.shln(1, log2))), Ntt.dft(a, R.Fr.inv(Ntt.omega(log2)), log2))

def Ntt.coset_fft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.fft(Ntt.powers.loop(Nat.pow(2n, log2), 0n, Ntt.gen(), R.Fr.one(), a), log2)

def Ntt.coset_ifft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.powers.loop(Nat.pow(2n, log2), 0n, R.Fr.inv(Ntt.gen()), R.Fr.one(), Ntt.ifft(a, log2))

# a[i] = (a[i] * b[i] - c[i]) * z
def Ntt.pw.s2(+i: Nat, z: R.Fr, x: R.Fr, y: R.Fr, a: Array<U32>, b: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & Array<U32>):
  (c, w) = r
  (R.Fr.to_array(a, i, R.Fr.mul(R.Fr.sub(R.Fr.mul(x, y), w), z)), (b, c))

def Ntt.pw.s1(+i: Nat, z: R.Fr, x: R.Fr, a: Array<U32>, c: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & Array<U32>):
  (b, y) = r
  Ntt.pw.s2(i, z, x, y, a, b, R.Fr.from_array(c, i))

def Ntt.pw.s0(+i: Nat, z: R.Fr, b: Array<U32>, c: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & Array<U32>):
  (a, x) = r
  Ntt.pw.s1(i, z, x, a, c, R.Fr.from_array(b, i))

def Ntt.pw.loop(n: Nat, +i: Nat, +z: R.Fr, st: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & Array<U32>):
  match n:
    case 0n:
      st
    case 1n+m:
      (a, r) = st
      (b, c) = r
      Ntt.pw.loop(m, (i + 1n), z, Ntt.pw.s0(i, z, b, c, R.Fr.from_array(a, i)))

def Ntt.pw.done(st: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32>:
  (a, r) = st
  a

# h = (A*B - C) / Z_d on the coset g*H, as arkworks' witness_map_from_matrices:
# ifft each, coset_fft each, pointwise (ab - c) * (g^d - 1)^-1, coset_ifft
def Ntt.qap_h(a: Array<U32>, b: Array<U32>, c: Array<U32>, +log2: Nat) -> Array<U32>:
  ea eb ec = Ntt.coset_fft(Ntt.ifft(a, log2), log2) Ntt.coset_fft(Ntt.ifft(b, log2), log2) Ntt.coset_fft(Ntt.ifft(c, log2), log2)
  +zinv = R.Fr.inv(R.Fr.sub(Ntt.sqr_n(log2, Ntt.gen()), R.Fr.one()))
  Ntt.coset_ifft(Ntt.pw.done(Ntt.pw.loop(Nat.pow(2n, log2), 0n, zinv, (ea, (eb, ec)))), log2)
