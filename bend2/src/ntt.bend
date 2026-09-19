# Radix-2 NTT / iNTT / coset variants over BN254 Fr (Montgomery, 16 words per element,
# bend2/FORMAT.md) for Bend 2, plus Ntt.qap_h = ark-groth16 LibsnarkReduction's h(x).
#
# Shape: the 2^log2 elements live in a binary tree of 2^fd contiguous chunk arrays
# (NTree; built from the flat array by ANode halving = memcpy-cheap, joined back the same
# way). A transform is log2 Stockham (autosort, natural order in and out) stages; every
# stage maps chunk pairs to chunk pairs so each stage is a balanced fork tree of 2^(fd-1)
# leaf tasks with no shared arrays:
#   stage s < fd  ("early"): pairs chunk c with chunk c + 2^(fd-1-s) (same position in
#                 the two halves of a depth-s subtree), one twiddle w = ω_{2^(s+1)}^q per
#                 subtree q:   lo[i] = e[i] + w o[i],  hi[i] = e[i] - w o[i]
#   stage s >= fd ("late"):  pairs chunks 2c, 2c+1 (src = their concatenation), blocks of
#                 h = n / 2^(s+1) butterflies, twiddle ω_n^(c m) ω_{2^(s+1)}^q for block q
#                 (running product):  lo[qh+b] = src[2qh+b] + w src[2qh+b+h], hi = e - w o
# The lo results of a stage form the first half of the next state, the hi results the
# second half (k-major Stockham layout Y_s[k N_s + b]; Y_0 = input, Y_log2 = output).
# Twiddles are computed at runtime from the generated Montgomery constants below; no
# twiddle tables (the running products cost ~1 extra mul per h butterflies).
import Base
import ./fr.bend as F

# BEGIN GENERATED (bend2/gen/gen_ntt.py)
# TWO_ADIC_ROOT_OF_UNITY (order 2^28) (Montgomery)
def Ntt.root() -> F.Fr:
  F.Fr{15772, 32977, 29525, 25454, 65494, 9285, 62324, 41515, 984, 7858, 10944, 22085, 63975, 10595, 61332, 6240}

# its inverse (Montgomery)
def Ntt.root_inv() -> F.Fr:
  F.Fr{46723, 22603, 49174, 35260, 42252, 356, 34943, 59609, 55869, 31070, 38347, 30046, 45360, 4899, 11143, 3927}

# coset generator g = Fr::GENERATOR = 5 (Montgomery)
def Ntt.gen() -> F.Fr:
  F.Fr{65510, 40959, 3833, 6925, 37183, 41770, 26787, 60090, 1673, 55517, 60278, 18392, 48067, 8437, 2133, 5584}

# g^-1 (Montgomery)
def Ntt.gen_inv() -> F.Fr:
  F.Fr{39321, 2457, 14708, 55109, 61352, 33731, 42964, 46253, 12641, 58751, 41720, 50332, 27827, 44053, 14164, 5674}

# 2^-1 (n^-1 = two_inv^log2) (Montgomery)
def Ntt.two_inv() -> F.Fr:
  F.Fr{65534, 8191, 5336, 30780, 7901, 3213, 12143, 44952, 20293, 64765, 29842, 36703, 49068, 15772, 25370, 7991}

# END GENERATED

# ---- field helpers ----

def Ntt.pow.bit(r: Nat, +x: F.Fr, acc: F.Fr) -> F.Fr:
  match r:
    case 0n:
      acc
    case 1n++p:
      F.Fr.mul(acc, x)

def Ntt.pow.go(fuel: Nat, +e: Nat, +x: F.Fr, acc: F.Fr) -> F.Fr:
  match fuel:
    case 0n:
      acc
    case 1n++p:
      Ntt.pow.go(p, (e / 2n), F.Fr.sqr(x), Ntt.pow.bit((e % 2n), x, acc))

# x^e for e < 2^bits (square-and-multiply)
def Ntt.pow(+x: F.Fr, e: Nat, bits: Nat) -> F.Fr:
  Ntt.pow.go(bits, e, x, F.Fr.one())

# x^(2^n)
def Ntt.sqr_n(n: Nat, x: F.Fr) -> F.Fr:
  match n:
    case 0n:
      x
    case 1n++p:
      Ntt.sqr_n(p, F.Fr.sqr(x))

# ω_k = root^(2^(28-k)): generator of arkworks' Radix2EvaluationDomain of size 2^k (k <= 28)
def Ntt.omega(k: Nat) -> F.Fr:
  Ntt.sqr_n(Nat.sub(28n, k), Ntt.root())

def Ntt.omega_inv(k: Nat) -> F.Fr:
  Ntt.sqr_n(Nat.sub(28n, k), Ntt.root_inv())

# ---- chunk tree ----

type NTree is Type:
  NLeaf{a: Array<U32>}
  NNode{l: NTree, r: NTree}

# split the flat 2^(log2+4)-word array into 2^fd chunk leaves (ANode halves)
def Ntt.to_tree(fd: Nat, a: Array<U32>) -> NTree:
  match fd:
    case 0n:
      NLeaf{a}
    case 1n++p:
      match a:
        case ALeaf{x}:
          NLeaf{ALeaf{x}}
        case ANode{xs, ys}:
          l r = Ntt.to_tree(p, xs) Ntt.to_tree(p, ys)
          NNode{l, r}

def Ntt.to_array(t: NTree) -> Array<U32>:
  match t:
    case NLeaf{a}:
      a
    case NNode{l, r}:
      x y = Ntt.to_array(l) Ntt.to_array(r)
      ANode{x, y}

def Ntt.join2(x: NTree & NTree, y: NTree & NTree) -> NTree & NTree:
  (xl, xh) = x
  (yl, yh) = y
  (NNode{xl, yl}, NNode{xh, yh})

def Ntt.pair_node(p: NTree & NTree) -> NTree:
  (lo, hi) = p
  NNode{lo, hi}

# ---- early stage: constant twiddle, lo[i] = e[i] + w o[i], hi[i] = e[i] - w o[i] ----

type NBf is Type:
  NBf{e: Array<U32>, o: Array<U32>, lo: Array<U32>, hi: Array<U32>}

def Ntt.bfc.s1(+i: Nat, +w: F.Fr, ea: Array<U32>, lo: Array<U32>, hi: Array<U32>, +e: F.Fr, pr: Array<U32> & F.Fr) -> NBf:
  (oa, o) = pr
  +t = F.Fr.mul(w, o)
  NBf{ea, oa, F.Fr.to_array(lo, i, F.Fr.add(e, t)), F.Fr.to_array(hi, i, F.Fr.sub(e, t))}

def Ntt.bfc.s0(+i: Nat, +w: F.Fr, oa: Array<U32>, lo: Array<U32>, hi: Array<U32>, pr: Array<U32> & F.Fr) -> NBf:
  (ea, +e) = pr
  Ntt.bfc.s1(i, w, ea, lo, hi, e, F.Fr.from_array(oa, i))

def Ntt.bfc(n: Nat, +i: Nat, +w: F.Fr, st: NBf) -> NBf:
  match n:
    case 0n:
      st
    case 1n++p:
      NBf{ea, oa, lo, hi} = st
      Ntt.bfc(p, (i + 1n), w, Ntt.bfc.s0(i, w, oa, lo, hi, F.Fr.from_array(ea, i)))

def Ntt.early.fin(st: NBf) -> NTree & NTree:
  NBf{ea, oa, lo, hi} = st
  (NLeaf{lo}, NLeaf{hi})

# chunk pair (m = 2^lm elements each) -> (lo chunk, hi chunk)
def Ntt.early.leaf(a: Array<U32>, b: Array<U32>, +lm: Nat, w: F.Fr) -> NTree & NTree:
  Ntt.early.fin(Ntt.bfc(Nat.pow(2n, lm), 0n, w, NBf{a, b, Array.new(U32, (lm + 4n), 0), Array.new(U32, (lm + 4n), 0)}))

# zip the two halves of a depth-s subtree leaf by leaf
def Ntt.early.zip(l: NTree, r: NTree, +lm: Nat, +w: F.Fr) -> NTree & NTree:
  match l r:
    case NLeaf{a} NLeaf{b}:
      Ntt.early.leaf(a, b, lm, w)
    case NNode{l1, r1} NNode{l2, r2}:
      x y = Ntt.early.zip(l1, l2, lm, w) Ntt.early.zip(r1, r2, lm, w)
      Ntt.join2(x, y)
    case NLeaf{a} NNode{l2, r2}:
      (NLeaf{a}, NNode{l2, r2})
    case NNode{l1, r1} NLeaf{b}:
      (NNode{l1, r1}, NLeaf{b})

# descend d levels, then zip the subtree's halves with w = ws^q (q = subtree index, built
# top-down: left child w^2, right child w^2 ws), ws = ω_{2^(s+1)}
def Ntt.early(d: Nat, t: NTree, +w: F.Fr, +lm: Nat, +ws: F.Fr) -> NTree & NTree:
  match d:
    case 0n:
      match t:
        case NNode{l, r}:
          Ntt.early.zip(l, r, lm, w)
        case NLeaf{a}:
          (NLeaf{a}, NLeaf{Array.new(U32, 0n, 0)})
    case 1n++p:
      match t:
        case NNode{l, r}:
          +w2 = F.Fr.sqr(w)
          x y = Ntt.early(p, l, w2, lm, ws) Ntt.early(p, r, F.Fr.mul(w2, ws), lm, ws)
          Ntt.join2(x, y)
        case NLeaf{a}:
          (NLeaf{a}, NLeaf{Array.new(U32, 0n, 0)})

# ---- late stage: running twiddle over blocks of h butterflies ----

type NBr is Type:
  NBr{src: Array<U32>, lo: Array<U32>, hi: Array<U32>, +w: F.Fr}

def Ntt.bfr.s1(+d: Nat, +w: F.Fr, lo: Array<U32>, hi: Array<U32>, +e: F.Fr, pr: Array<U32> & F.Fr) -> NBr:
  (src, o) = pr
  +t = F.Fr.mul(w, o)
  NBr{src, F.Fr.to_array(lo, d, F.Fr.add(e, t)), F.Fr.to_array(hi, d, F.Fr.sub(e, t)), w}

def Ntt.bfr.s0(+s1: Nat, +d: Nat, +w: F.Fr, lo: Array<U32>, hi: Array<U32>, pr: Array<U32> & F.Fr) -> NBr:
  (src, +e) = pr
  Ntt.bfr.s1(d, w, lo, hi, e, F.Fr.from_array(src, s1))

# one block: lo[d0+b] = src[s0+b] + w src[s0+h+b], hi[d0+b] = src[s0+b] - w src[s0+h+b], b < h
def Ntt.bfr.blk(n: Nat, +b: Nat, +s0: Nat, +d0: Nat, +h: Nat, st: NBr) -> NBr:
  match n:
    case 0n:
      st
    case 1n++p:
      NBr{src, lo, hi, w} = st
      Ntt.bfr.blk(p, (b + 1n), s0, d0, h, Ntt.bfr.s0((s0 + h + b), (d0 + b), w, lo, hi, F.Fr.from_array(src, (s0 + b))))

def Ntt.bfr.upd(+ratio: F.Fr, st: NBr) -> NBr:
  NBr{src, lo, hi, w} = st
  NBr{src, lo, hi, F.Fr.mul(w, ratio)}

# nq blocks: block q reads src[2qh ..], writes lo/hi[off + qh ..], twiddle w ratio^q
def Ntt.bfr(nq: Nat, +q: Nat, +h: Nat, +off: Nat, +ratio: F.Fr, st: NBr) -> NBr:
  match nq:
    case 0n:
      st
    case 1n++p:
      Ntt.bfr(p, (q + 1n), h, off, ratio, Ntt.bfr.upd(ratio, Ntt.bfr.blk(h, 0n, (2n * q * h), (off + q * h), h, st)))

def Ntt.late.fin(st: NBr) -> NTree & NTree:
  NBr{src, lo, hi, w} = st
  (NLeaf{lo}, NLeaf{hi})

# second half of the pair: blocks read chunk b, write at offset m/2 = nq h, twiddle continues
def Ntt.late.b(b: Array<U32>, +h: Nat, +nq: Nat, +ratio: F.Fr, st: NBr) -> NTree & NTree:
  NBr{a, lo, hi, w} = st
  Ntt.late.fin(Ntt.bfr(nq, 0n, h, (nq * h), ratio, NBr{b, lo, hi, w}))

# chunks 2c, 2c+1 (m = 2^lm elements each; h <= m/2) -> (lo chunk c, hi chunk c)
def Ntt.late.leaf(a: Array<U32>, b: Array<U32>, +lm: Nat, +h: Nat, w: F.Fr, +ratio: F.Fr) -> NTree & NTree:
  +nq = (Nat.pow(2n, lm) / (2n * h))
  Ntt.late.b(b, h, nq, ratio, Ntt.bfr(nq, 0n, h, 0n, ratio, NBr{a, Array.new(U32, (lm + 4n), 0), Array.new(U32, (lm + 4n), 0), w}))

# descend d = fd-1 levels, then butterfly the leaf pair c with start twiddle w = ω_n^(c m)
# (built top-down: left child w^2, right child w^2 wm, wm = ω_n^m)
def Ntt.late(d: Nat, t: NTree, +w: F.Fr, +lm: Nat, +h: Nat, +wm: F.Fr, +ratio: F.Fr) -> NTree & NTree:
  match d:
    case 0n:
      match t:
        case NNode{l, r}:
          match l r:
            case NLeaf{a} NLeaf{b}:
              Ntt.late.leaf(a, b, lm, h, w, ratio)
            case NLeaf{a} NNode{l2, r2}:
              (NLeaf{a}, NNode{l2, r2})
            case NNode{l1, r1} NLeaf{b}:
              (NNode{l1, r1}, NLeaf{b})
            case NNode{l1, r1} NNode{l2, r2}:
              (NNode{l1, r1}, NNode{l2, r2})
        case NLeaf{a}:
          (NLeaf{a}, NLeaf{Array.new(U32, 0n, 0)})
    case 1n++p:
      match t:
        case NNode{l, r}:
          +w2 = F.Fr.sqr(w)
          x y = Ntt.late(p, l, w2, lm, h, wm, ratio) Ntt.late(p, r, F.Fr.mul(w2, wm), lm, h, wm, ratio)
          Ntt.join2(x, y)
        case NLeaf{a}:
          (NLeaf{a}, NLeaf{Array.new(U32, 0n, 0)})

# ---- stages ----

def Ntt.stage.go(early: Bool, +s: Nat, t: NTree, +fd: Nat, +lm: Nat, +j: Nat, ws: F.Fr, wn: F.Fr) -> NTree:
  match early:
    case True{}:
      Ntt.pair_node(Ntt.early(s, t, F.Fr.one(), lm, ws))
    case False{}:
      Ntt.pair_node(Ntt.late(Nat.sub(fd, 1n), t, F.Fr.one(), lm, Nat.pow(2n, j), Ntt.sqr_n(lm, wn), ws))

# stage s: j = log2 - s - 1, h = 2^j, ω_{2^(s+1)} = wn^(2^j)
def Ntt.stage(early: Bool, +s: Nat, t: NTree, +fd: Nat, +lm: Nat, +log2: Nat, +wn: F.Fr) -> NTree:
  +j = Nat.sub(Nat.sub(log2, s), 1n)
  Ntt.stage.go(early, s, t, fd, lm, j, Ntt.sqr_n(j, wn), wn)

def Ntt.stages(n: Nat, +s: Nat, t: NTree, +fd: Nat, +lm: Nat, +log2: Nat, +wn: F.Fr) -> NTree:
  match n:
    case 0n:
      t
    case 1n++p:
      Ntt.stages(p, (s + 1n), Ntt.stage(Nat.is_lt(s, fd), s, t, fd, lm, log2, wn), fd, lm, log2, wn)

# all log2 stages of a 2^fd-chunk tree; wn = ω_n (forward) or ω_n^-1 (inverse, unscaled)
def Ntt.core(t: NTree, +log2: Nat, +fd: Nat, wn: F.Fr) -> NTree:
  Ntt.stages(log2, 0n, t, fd, Nat.sub(log2, fd), log2, wn)

# ---- scaling: x[j] *= start ratio^j over the whole tree ----

type NSc is Type:
  NSc{a: Array<U32>, +v: F.Fr}

def Ntt.scale.s0(+i: Nat, +v: F.Fr, ratio: F.Fr, pr: Array<U32> & F.Fr) -> NSc:
  (a, x) = pr
  NSc{F.Fr.to_array(a, i, F.Fr.mul(x, v)), F.Fr.mul(v, ratio)}

def Ntt.scale.loop(n: Nat, +i: Nat, +ratio: F.Fr, st: NSc) -> NSc:
  match n:
    case 0n:
      st
    case 1n++p:
      NSc{a, v} = st
      Ntt.scale.loop(p, (i + 1n), ratio, Ntt.scale.s0(i, v, ratio, F.Fr.from_array(a, i)))

def Ntt.scale.fin(st: NSc) -> NTree:
  NSc{a, v} = st
  NLeaf{a}

# chunk c holds elements c m .. (c+1) m - 1; rc = ratio^(c m) built top-down (ratm = ratio^m)
def Ntt.scale.t(t: NTree, +rc: F.Fr, +lm: Nat, +start: F.Fr, +ratio: F.Fr, +ratm: F.Fr) -> NTree:
  match t:
    case NLeaf{a}:
      Ntt.scale.fin(Ntt.scale.loop(Nat.pow(2n, lm), 0n, ratio, NSc{a, F.Fr.mul(start, rc)}))
    case NNode{l, r}:
      +r2 = F.Fr.sqr(rc)
      x y = Ntt.scale.t(l, r2, lm, start, ratio, ratm) Ntt.scale.t(r, F.Fr.mul(r2, ratm), lm, start, ratio, ratm)
      NNode{x, y}

# x[j] *= start ratio^j over the whole tree (m = 2^lm elements per chunk)
def Ntt.scale(t: NTree, +lm: Nat, +start: F.Fr, +ratio: F.Fr) -> NTree:
  Ntt.scale.t(t, F.Fr.one(), lm, start, ratio, Ntt.sqr_n(lm, ratio))

# ---- tree-level transforms ----

def Ntt.t_fft(t: NTree, +log2: Nat, +fd: Nat) -> NTree:
  Ntt.core(t, log2, fd, Ntt.omega(log2))

# n^-1 = two_inv^log2
def Ntt.t_ifft(t: NTree, +log2: Nat, +fd: Nat) -> NTree:
  Ntt.scale(Ntt.core(t, log2, fd, Ntt.omega_inv(log2)), Nat.sub(log2, fd), Ntt.pow(Ntt.two_inv(), log2, 6n), F.Fr.one())

# evaluations over the coset g H: fft of (a_j g^j)
def Ntt.t_coset_fft(t: NTree, +log2: Nat, +fd: Nat) -> NTree:
  Ntt.core(Ntt.scale(t, Nat.sub(log2, fd), F.Fr.one(), Ntt.gen()), log2, fd, Ntt.omega(log2))

def Ntt.t_coset_ifft(t: NTree, +log2: Nat, +fd: Nat) -> NTree:
  Ntt.scale(Ntt.core(t, log2, fd, Ntt.omega_inv(log2)), Nat.sub(log2, fd), Ntt.pow(Ntt.two_inv(), log2, 6n), Ntt.gen_inv())

# ---- pointwise (a b - c) z over three trees ----

type NP3 is Type:
  NP3{a: Array<U32>, b: Array<U32>, c: Array<U32>}

def Ntt.point.s2(+i: Nat, z: F.Fr, a: Array<U32>, b: Array<U32>, x: F.Fr, pr: Array<U32> & F.Fr) -> NP3:
  (c, y) = pr
  NP3{a, b, F.Fr.to_array(c, i, F.Fr.mul(F.Fr.sub(x, y), z))}

def Ntt.point.s1(+i: Nat, z: F.Fr, a: Array<U32>, c: Array<U32>, x: F.Fr, pr: Array<U32> & F.Fr) -> NP3:
  (b, y) = pr
  Ntt.point.s2(i, z, a, b, F.Fr.mul(x, y), F.Fr.from_array(c, i))

def Ntt.point.s0(+i: Nat, z: F.Fr, b: Array<U32>, c: Array<U32>, pr: Array<U32> & F.Fr) -> NP3:
  (a, x) = pr
  Ntt.point.s1(i, z, a, c, x, F.Fr.from_array(b, i))

def Ntt.point.loop(n: Nat, +i: Nat, +z: F.Fr, st: NP3) -> NP3:
  match n:
    case 0n:
      st
    case 1n++p:
      NP3{a, b, c} = st
      Ntt.point.loop(p, (i + 1n), z, Ntt.point.s0(i, z, b, c, F.Fr.from_array(a, i)))

def Ntt.point.fin(st: NP3) -> NTree:
  NP3{a, b, c} = st
  NLeaf{c}

def Ntt.point(d: Nat, ta: NTree, tb: NTree, tc: NTree, +lm: Nat, +z: F.Fr) -> NTree:
  match d:
    case 0n:
      match ta:
        case NLeaf{a}:
          match tb:
            case NLeaf{b}:
              match tc:
                case NLeaf{c}:
                  Ntt.point.fin(Ntt.point.loop(Nat.pow(2n, lm), 0n, z, NP3{a, b, c}))
                case NNode{l3, r3}:
                  NNode{l3, r3}
            case NNode{l2, r2}:
              NNode{l2, r2}
        case NNode{l1, r1}:
          NNode{l1, r1}
    case 1n++p:
      match ta:
        case NNode{l1, r1}:
          match tb:
            case NNode{l2, r2}:
              match tc:
                case NNode{l3, r3}:
                  x y = Ntt.point(p, l1, l2, l3, lm, z) Ntt.point(p, r1, r2, r3, lm, z)
                  NNode{x, y}
                case NLeaf{c}:
                  NLeaf{c}
            case NLeaf{b}:
              NLeaf{b}
        case NLeaf{a}:
          NLeaf{a}

# ---- flat API (frozen) ----

# fork depth: 2^fd chunks of >= 1 element, up to 4096 chunks (the M4 has 4P + 6E cores and
# no work stealing, so a stage needs many more tasks than cores to balance)
def Ntt.fd(log2: Nat) -> Nat:
  Nat.max(1n, Nat.min(12n, Nat.sub(log2, 1n)))

def Ntt.fft_fd.go(z: Bool, a: Array<U32>, +log2: Nat, +fd: Nat) -> Array<U32>:
  match z:
    case True{}:
      a
    case False{}:
      Ntt.to_array(Ntt.t_fft(Ntt.to_tree(fd, a), log2, fd))

def Ntt.ifft_fd.go(z: Bool, a: Array<U32>, +log2: Nat, +fd: Nat) -> Array<U32>:
  match z:
    case True{}:
      a
    case False{}:
      Ntt.to_array(Ntt.t_ifft(Ntt.to_tree(fd, a), log2, fd))

def Ntt.coset_fft_fd.go(z: Bool, a: Array<U32>, +log2: Nat, +fd: Nat) -> Array<U32>:
  match z:
    case True{}:
      a
    case False{}:
      Ntt.to_array(Ntt.t_coset_fft(Ntt.to_tree(fd, a), log2, fd))

def Ntt.coset_ifft_fd.go(z: Bool, a: Array<U32>, +log2: Nat, +fd: Nat) -> Array<U32>:
  match z:
    case True{}:
      a
    case False{}:
      Ntt.to_array(Ntt.t_coset_ifft(Ntt.to_tree(fd, a), log2, fd))

# clamp a requested fork depth into 1 <= fd < log2
def Ntt.clamp(+log2: Nat, fd: Nat) -> Nat:
  Nat.max(1n, Nat.min(fd, Nat.sub(log2, 1n)))

# explicit fork depth (clamped to 1 <= fd < log2); the bench sweeps it and calls these with `!` for the GPU
def Ntt.fft_fd(a: Array<U32>, +log2: Nat, fd: Nat) -> Array<U32>:
  Ntt.fft_fd.go(Nat.is_eq(log2, 0n), a, log2, Ntt.clamp(log2, fd))

def Ntt.ifft_fd(a: Array<U32>, +log2: Nat, fd: Nat) -> Array<U32>:
  Ntt.ifft_fd.go(Nat.is_eq(log2, 0n), a, log2, Ntt.clamp(log2, fd))

def Ntt.coset_fft_fd(a: Array<U32>, +log2: Nat, fd: Nat) -> Array<U32>:
  Ntt.coset_fft_fd.go(Nat.is_eq(log2, 0n), a, log2, Ntt.clamp(log2, fd))

def Ntt.coset_ifft_fd(a: Array<U32>, +log2: Nat, fd: Nat) -> Array<U32>:
  Ntt.coset_ifft_fd.go(Nat.is_eq(log2, 0n), a, log2, Ntt.clamp(log2, fd))

# 2^log2 Fr coefficients (Montgomery, natural order) -> evaluations over arkworks' radix-2 domain
def Ntt.fft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.fft_fd(a, log2, Ntt.fd(log2))

def Ntt.ifft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.ifft_fd(a, log2, Ntt.fd(log2))

# coset g H with g = 5
def Ntt.coset_fft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.coset_fft_fd(a, log2, Ntt.fd(log2))

def Ntt.coset_ifft(a: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.coset_ifft_fd(a, log2, Ntt.fd(log2))

# ifft then coset_fft (one of the three a/b/c pipelines): the ifft's n^-1 and the coset's
# g^j are one scale pass (x[j] *= n^-1 g^j) instead of t_ifft's scale followed by t_coset_fft's
def Ntt.qap_h.pipe(a: Array<U32>, +log2: Nat, +fd: Nat) -> NTree:
  Ntt.core(Ntt.scale(Ntt.core(Ntt.to_tree(fd, a), log2, fd, Ntt.omega_inv(log2)), Nat.sub(log2, fd), Ntt.pow(Ntt.two_inv(), log2, 6n), Ntt.gen()), log2, fd, Ntt.omega(log2))

# h(x) = (A B - C) / Z_d over the coset, Z_d(g ω^i) = g^d - 1, exactly ark-groth16's
# LibsnarkReduction::witness_map_from_matrices; output natural-order coefficients
def Ntt.qap_h_fd.go(a: Array<U32>, b: Array<U32>, c: Array<U32>, +log2: Nat, +fd: Nat) -> Array<U32>:
  ta tb tc = Ntt.qap_h.pipe(a, log2, fd) Ntt.qap_h.pipe(b, log2, fd) Ntt.qap_h.pipe(c, log2, fd)
  +zinv = F.Fr.inv(F.Fr.sub(Ntt.sqr_n(log2, Ntt.gen()), F.Fr.one()))
  Ntt.to_array(Ntt.t_coset_ifft(Ntt.point(fd, ta, tb, tc, Nat.sub(log2, fd), zinv), log2, fd))

def Ntt.qap_h_fd(a: Array<U32>, b: Array<U32>, c: Array<U32>, +log2: Nat, fd: Nat) -> Array<U32>:
  Ntt.qap_h_fd.go(a, b, c, log2, Ntt.clamp(log2, fd))

def Ntt.qap_h(a: Array<U32>, b: Array<U32>, c: Array<U32>, +log2: Nat) -> Array<U32>:
  Ntt.qap_h_fd(a, b, c, log2, Ntt.fd(log2))
