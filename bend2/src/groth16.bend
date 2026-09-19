# Groth16 prover pieces independent of the MSM/NTT modules: header + input loading,
# R1CS evaluation vectors, scalar conversion, and the final A/B/C combination
# (ref/README.md "Reproducing proof_ref.json bit-for-bit"). Arrays are single-owner, so
# every phase takes the whole prover state `S` and returns it; consumed inputs are
# replaced by `Groth.empty()`. Layout of all inputs: bend2/FORMAT.md.
import Base
import ./fr.bend as R
import ./g1.bend as G
import ./g2.bend as G2
import ./bin_io.bend as Io

# header.bin: num_constraints, num_instance, num_witness, domain_log2, n_a, n_b, n_h, n_l
type Hdr is Data:
  Hdr{+nc: U32, +ni: U32, +nw: U32, +lg: U32, +na: U32, +nb: U32, +nh: U32, +nl: U32}

# prover state: z (witness, Montgomery then canonical), zl (z[2..] canonical, l_query scalars),
# ca/cb/cc (CSR matrices), ea/eb/ec (evaluation vectors), hh (h coefficients, canonical),
# g1 = [alpha beta delta], g2 = [beta delta], pa/pb1/pb2/ph/pl = queries, res1 = affine G1
# accumulators [A B1 C] (MSM sums until Groth.combine), res2 = the G2 one [B2], r/s.
# (A record is limited to 255 flattened words, hence points live in arrays, not fields.)
type S is Type:
  S{+h: Hdr, z: Array<U32>, zl: Array<U32>, ca: Array<U32>, cb: Array<U32>, cc: Array<U32>, ea: Array<U32>, eb: Array<U32>, ec: Array<U32>, hh: Array<U32>, g1: Array<U32>, g2: Array<U32>, pa: Array<U32>, pb1: Array<U32>, pb2: Array<U32>, ph: Array<U32>, pl: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr}

# the finished proof, affine
type Out is Data:
  Out{+a: G.G1Aff, +b: G2.G2Aff, +c: G.G1Aff}

def Groth.empty() -> Array<U32>:
  Array.new(U32, 0n, 0)

# ---------------------------------------------------------------- header

def Hdr.s7(+nc: U32, +ni: U32, +nw: U32, +lg: U32, +na: U32, +nb: U32, +nh: U32, p: Array<U32> & U32) -> Hdr:
  (a, +nl) = p
  Hdr{nc, ni, nw, lg, na, nb, nh, nl}

def Hdr.s6(+nc: U32, +ni: U32, +nw: U32, +lg: U32, +na: U32, +nb: U32, p: Array<U32> & U32) -> Hdr:
  (a, +nh) = p
  Hdr.s7(nc, ni, nw, lg, na, nb, nh, a[7])

def Hdr.s5(+nc: U32, +ni: U32, +nw: U32, +lg: U32, +na: U32, p: Array<U32> & U32) -> Hdr:
  (a, +nb) = p
  Hdr.s6(nc, ni, nw, lg, na, nb, a[6])

def Hdr.s4(+nc: U32, +ni: U32, +nw: U32, +lg: U32, p: Array<U32> & U32) -> Hdr:
  (a, +na) = p
  Hdr.s5(nc, ni, nw, lg, na, a[5])

def Hdr.s3(+nc: U32, +ni: U32, +nw: U32, p: Array<U32> & U32) -> Hdr:
  (a, +lg) = p
  Hdr.s4(nc, ni, nw, lg, a[4])

def Hdr.s2(+nc: U32, +ni: U32, p: Array<U32> & U32) -> Hdr:
  (a, +nw) = p
  Hdr.s3(nc, ni, nw, a[3])

def Hdr.s1(+nc: U32, p: Array<U32> & U32) -> Hdr:
  (a, +ni) = p
  Hdr.s2(nc, ni, a[2])

def Hdr.s0(p: Array<U32> & U32) -> Hdr:
  (a, +nc) = p
  Hdr.s1(nc, a[1])

def Hdr.read(a: Array<U32>) -> Hdr:
  Hdr.s0(a[0])

# ---------------------------------------------------------------- small helpers

# ceil(log2(w)) for 1 <= w <= 2^31: the number of k in 0..30 with 2^k < w
def Groth.clog2.go(k: Nat, +w: U32) -> Nat:
  match k:
    case 0n:
      0n
    case 1n++m:
      (Groth.clog2.go(m, w) + U32.to_nat(U32.shrn(U32.sub(U32.shln(1, m), w), 31n)))

def Groth.clog2(+w: U32) -> Nat:
  Groth.clog2.go(31n, w)

# the first little-endian u32 of a file (the CSR nnz, needed to size the array)
def Groth.word.bytes(bs: List<&2, U32>) -> U32:
  match bs:
    case Nil{}:
      0
    case Con{b, t}:
      U32.or(b, U32.shln(Groth.word.bytes(t), 8n))

def Groth.word.res(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> U32:
  match r:
    case Done{bs}:
      Groth.word.bytes(bs)
    case Fail{e}:
      0

def Groth.word.fin(rd: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(U32):
  (f, r) = rd
  do IO<U32>:
    File.close(f)
    return Groth.word.res(r)

def Groth.first_word(path: String) -> IO(U32):
  do IO<U32>:
    f : File <- IO.try(File, File.open(path, "r"))
    rd : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 4)
    v : U32 <- Groth.word.fin(rd)
    return v

# ---------------------------------------------------------------- evaluation vectors
# CSR file words: [nnz][offs[0..N]][entries: col, 16-word coeff]; entry e starts at word 2 + N + 17e

def Ev.ent.s2.fin(one: Bool, acc: R.Fr, coef: R.Fr, zv: R.Fr) -> R.Fr:
  match one:
    case True{}:
      R.Fr.add(acc, zv)
    case False{}:
      R.Fr.add(acc, R.Fr.mul(coef, zv))

# acc + coef z[col]; a coefficient of 1 (Montgomery R, the common case) skips the Fr.mul
def Ev.ent.s2(acc: R.Fr, +coef: R.Fr, csr: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & R.Fr):
  (z, zv) = r
  (csr, (z, Ev.ent.s2.fin(U32.is_eq(R.Fr.eq(coef, R.Fr.one()), 1), acc, coef, zv)))

def Ev.ent.s1(acc: R.Fr, +col: U32, z: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & (Array<U32> & R.Fr):
  (csr, coef) = r
  Ev.ent.s2(acc, coef, csr, R.Fr.from_array(z, U32.to_nat(col)))

def Ev.ent.s0(acc: R.Fr, +w: U32, z: Array<U32>, r: Array<U32> & U32) -> Array<U32> & (Array<U32> & R.Fr):
  (csr, +col) = r
  Ev.ent.s1(acc, col, z, R.Fr.from_array.s0((w + 1 : U32), csr[(w + 1 : U32)]))

# accumulate n entries starting at word w: acc += coeff * z[col]
def Ev.ents(n: Nat, +w: U32, st: Array<U32> & (Array<U32> & R.Fr)) -> Array<U32> & (Array<U32> & R.Fr):
  match n:
    case 0n:
      st
    case 1n+m:
      (csr, r) = st
      (z, acc) = r
      Ev.ents(m, (w + 17 : U32), Ev.ent.s0(acc, w, z, csr[w]))

def Ev.row.fin(+i: Nat, ev: Array<U32>, st: Array<U32> & (Array<U32> & R.Fr)) -> Array<U32> & (Array<U32> & Array<U32>):
  (csr, r) = st
  (z, acc) = r
  (csr, (z, R.Fr.to_array(ev, i, acc)))

def Ev.row.s1(+i: Nat, +base: U32, +o0: U32, ev: Array<U32>, z: Array<U32>, r: Array<U32> & U32) -> Array<U32> & (Array<U32> & Array<U32>):
  (csr, +o1) = r
  Ev.row.fin(i, ev, Ev.ents(U32.to_nat((o1 - o0 : U32)), (base + (o0 * 17 : U32) : U32), (csr, (z, R.Fr.zero()))))

def Ev.row.s0(+i: Nat, +base: U32, ev: Array<U32>, z: Array<U32>, r: Array<U32> & U32) -> Array<U32> & (Array<U32> & Array<U32>):
  (csr, +o0) = r
  Ev.row.s1(i, base, o0, ev, z, csr[(U32.from_nat(i) + 2 : U32)])

# ev[i] = sum over row i, for n rows from i; state = (csr, (z, ev)); base = 2 + N
def Ev.rows(n: Nat, +i: Nat, +base: U32, st: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & Array<U32>):
  match n:
    case 0n:
      st
    case 1n+m:
      (csr, r) = st
      (z, ev) = r
      Ev.rows(m, (i + 1n), base, Ev.row.s0(i, base, ev, z, csr[(U32.from_nat(i) + 1 : U32)]))

# evaluation vector of one matrix over the size-2^lg domain (rows >= N stay zero)
def Ev.matrix(csr: Array<U32>, z: Array<U32>, +nc: Nat, lg: Nat) -> Array<U32> & (Array<U32> & Array<U32>):
  Ev.rows(nc, 0n, (U32.from_nat(nc) + 2 : U32), (csr, (z, Array.new(U32, (lg + 4n), 0))))

# dst[doff + i] = src[soff + i] for n elements
def Ev.copy.s(+i: Nat, dst: Array<U32>, r: Array<U32> & R.Fr) -> Array<U32> & Array<U32>:
  (src, x) = r
  (src, R.Fr.to_array(dst, i, x))

def Ev.copy(n: Nat, +i: Nat, +soff: Nat, +doff: Nat, st: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match n:
    case 0n:
      st
    case 1n+m:
      (src, dst) = st
      Ev.copy(m, (i + 1n), soff, doff, Ev.copy.s((doff + i), dst, R.Fr.from_array(src, (soff + i))))

def Ev.rewrap(csr: Array<U32>, r: Array<U32> & Array<U32>) -> Array<U32> & (Array<U32> & Array<U32>):
  (z, ev) = r
  (csr, (z, ev))

# libsnark input-consistency rows: a[N + i] = z[i] for the ni instance variables
def Ev.matrix_a.fin(+ni: Nat, +nc: Nat, r: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & Array<U32>):
  (csr, rr) = r
  (z, ev) = rr
  Ev.rewrap(csr, Ev.copy(ni, 0n, 0n, nc, (z, ev)))

def Ev.matrix_a(csr: Array<U32>, z: Array<U32>, +nc: Nat, lg: Nat, +ni: Nat) -> Array<U32> & (Array<U32> & Array<U32>):
  Ev.matrix_a.fin(ni, nc, Ev.matrix(csr, z, nc, lg))

# all three vectors: (z, (ea, (eb, ec)))
def Ev.three.s3(ea: Array<U32>, eb: Array<U32>, r: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & (Array<U32> & Array<U32>)):
  (cc, rr) = r
  (z, ec) = rr
  (z, (ea, (eb, ec)))

def Ev.three.s2(cc: Array<U32>, ea: Array<U32>, +nc: Nat, +lg: Nat, r: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & (Array<U32> & Array<U32>)):
  (cb, rr) = r
  (z, eb) = rr
  Ev.three.s3(ea, eb, Ev.matrix(cc, z, nc, lg))

def Ev.three.s1(cb: Array<U32>, cc: Array<U32>, +nc: Nat, +lg: Nat, r: Array<U32> & (Array<U32> & Array<U32>)) -> Array<U32> & (Array<U32> & (Array<U32> & Array<U32>)):
  (ca, rr) = r
  (z, ea) = rr
  Ev.three.s2(cc, ea, nc, lg, Ev.matrix(cb, z, nc, lg))

def Ev.three(ca: Array<U32>, cb: Array<U32>, cc: Array<U32>, z: Array<U32>, +nc: Nat, +lg: Nat, ni: Nat) -> Array<U32> & (Array<U32> & (Array<U32> & Array<U32>)):
  Ev.three.s1(cb, cc, nc, lg, Ev.matrix_a(ca, z, nc, lg, ni))

# ---------------------------------------------------------------- scalars

# a[i] = to_canonical(a[i]) for n elements (MSM scalars are canonical)
def Sc.canon.s(+i: Nat, r: Array<U32> & R.Fr) -> Array<U32>:
  (a, x) = r
  R.Fr.to_array(a, i, R.Fr.to_canonical(x))

def Sc.canon(n: Nat, +i: Nat, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+m:
      Sc.canon(m, (i + 1n), Sc.canon.s(i, R.Fr.from_array(a, i)))

# ---------------------------------------------------------------- loading

def Groth.rs.s2(+r: R.Fr, p: Array<U32> & R.Fr) -> R.Fr & R.Fr:
  (a, s) = p
  (r, s)

def Groth.rs.s1(p: Array<U32> & R.Fr) -> R.Fr & R.Fr:
  (a, r) = p
  Groth.rs.s2(r, R.Fr.from_array(a, 1n))

def Groth.rs(a: Array<U32>) -> R.Fr & R.Fr:
  Groth.rs.s1(R.Fr.from_array(a, 0n))

def Groth.mk(+h: Hdr, z: Array<U32>, ca: Array<U32>, cb: Array<U32>, cc: Array<U32>, g1: Array<U32>, g2: Array<U32>, pa: Array<U32>, pb1: Array<U32>, pb2: Array<U32>, ph: Array<U32>, pl: Array<U32>, rs: R.Fr & R.Fr) -> S:
  (r, s) = rs
  S{h, z, Groth.empty(), ca, cb, cc, Groth.empty(), Groth.empty(), Groth.empty(), Groth.empty(), g1, g2, pa, pb1, pb2, ph, pl, Array.new(U32, 7n, 0), Array.new(U32, 6n, 0), r, s}

# load every input under dir (bend2/FORMAT.md); nza/nzb/nzc = nnz of the three CSR files
def Groth.load(+dir: String, h: Hdr, +nza: U32, +nzb: U32, +nzc: U32) -> IO(S):
  match h:
    case Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      do IO<S>:
        z : Array<U32> <- Io.load_u32(dir ++ "/witness.bin", Groth.clog2((na * 16 : U32)), 0)
        ca : Array<U32> <- Io.load_u32(dir ++ "/r1cs_a.bin", Groth.clog2((((nza * 17 : U32) + nc : U32) + 2 : U32)), 0)
        cb : Array<U32> <- Io.load_u32(dir ++ "/r1cs_b.bin", Groth.clog2((((nzb * 17 : U32) + nc : U32) + 2 : U32)), 0)
        cc : Array<U32> <- Io.load_u32(dir ++ "/r1cs_c.bin", Groth.clog2((((nzc * 17 : U32) + nc : U32) + 2 : U32)), 0)
        g1 : Array<U32> <- Io.load_u32(dir ++ "/pk_g1.bin", 7n, 0)
        g2 : Array<U32> <- Io.load_u32(dir ++ "/pk_g2.bin", 7n, 0)
        pa : Array<U32> <- Io.load_u32(dir ++ "/pk_a.bin", Groth.clog2((na * 32 : U32)), 0)
        pb1 : Array<U32> <- Io.load_u32(dir ++ "/pk_b1.bin", Groth.clog2((nb * 32 : U32)), 0)
        pb2 : Array<U32> <- Io.load_u32(dir ++ "/pk_b2.bin", Groth.clog2((nb * 64 : U32)), 0)
        ph : Array<U32> <- Io.load_u32(dir ++ "/pk_h.bin", Groth.clog2((nh * 32 : U32)), 0)
        pl : Array<U32> <- Io.load_u32(dir ++ "/pk_l.bin", Groth.clog2((nl * 32 : U32)), 0)
        rs : Array<U32> <- Io.load_u32(dir ++ "/rs.bin", 5n, 0)
        return Groth.mk(Hdr{nc, ni, nw, lg, na, nb, nh, nl}, z, ca, cb, cc, g1, g2, pa, pb1, pb2, ph, pl, Groth.rs(rs))

# ---------------------------------------------------------------- phase: evaluation vectors + canonical scalars

def Groth.evals.fin2(+h: Hdr, ea: Array<U32>, eb: Array<U32>, ec: Array<U32>, hh: Array<U32>, g1: Array<U32>, g2: Array<U32>, pa: Array<U32>, pb1: Array<U32>, pb2: Array<U32>, ph: Array<U32>, pl: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, p: Array<U32> & Array<U32>) -> S:
  match h:
    case Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      (z, zl) = p
      S{Hdr{nc, ni, nw, lg, na, nb, nh, nl}, z, zl, Groth.empty(), Groth.empty(), Groth.empty(), ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s}

def Groth.evals.fin(+h: Hdr, hh: Array<U32>, g1: Array<U32>, g2: Array<U32>, pa: Array<U32>, pb1: Array<U32>, pb2: Array<U32>, ph: Array<U32>, pl: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, p: Array<U32> & (Array<U32> & (Array<U32> & Array<U32>))) -> S:
  match h:
    case Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      (z, p1) = p
      (ea, p2) = p1
      (eb, ec) = p2
      Groth.evals.fin2(Hdr{nc, ni, nw, lg, na, nb, nh, nl}, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s, Ev.copy(U32.to_nat(nw), 0n, 2n, 0n, (Sc.canon(U32.to_nat(na), 0n, z), Array.new(U32, Groth.clog2((nw * 16 : U32)), 0))))

# ea/eb/ec over the domain (ea with the input-consistency rows), then z canonical and
# zl = z[2..] copied from it (converted once, not once per array)
def Groth.evals(st: S) -> S:
  S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Groth.evals.fin(Hdr{nc, ni, nw, lg, na, nb, nh, nl}, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s, Ev.three(ca, cb, cc, z, U32.to_nat(nc), U32.to_nat(lg), U32.to_nat(ni)))

# ---------------------------------------------------------------- MSM accumulators

# a[idx] += m (affine slots start at infinity = (0, 0))
def Groth.acc_g1.fin(+idx: Nat, m: G.G1, p: Array<U32> & G.G1Aff) -> Array<U32>:
  (a, cur) = p
  G.G1Aff.to_array(a, idx, G.G1.to_affine(G.G1.add_mixed(m, cur)))

def Groth.acc_g1(a: Array<U32>, +idx: Nat, m: G.G1) -> Array<U32>:
  Groth.acc_g1.fin(idx, m, G.G1Aff.from_array(a, idx))

def Groth.acc_g2.fin(+idx: Nat, m: G2.G2, p: Array<U32> & G2.G2Aff) -> Array<U32>:
  (a, cur) = p
  G2.G2Aff.to_array(a, idx, G2.G2.to_affine(G2.G2.add_mixed(m, cur)))

def Groth.acc_g2(a: Array<U32>, +idx: Nat, m: G2.G2) -> Array<U32>:
  Groth.acc_g2.fin(idx, m, G2.G2Aff.from_array(a, idx))

# ---------------------------------------------------------------- phase: combine
# A = alpha + msmA + r*delta; B1 = beta1 + msmB1 + s*delta1; B2 = beta2 + msmB2 + s*delta2;
# C = s*A + r*B1 - r*s*delta1 + (msmL + msmH); res1 = [msmA msmB1 msmL+msmH], res2 = [msmB2]

def Groth.combine.c9(+r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, +beta2: G2.G2Aff, +delta2: G2.G2Aff, +mA: G.G1Aff, +mB1: G.G1Aff, +mLH: G.G1Aff, p: Array<U32> & G2.G2Aff) -> Out:
  (res2, +mB2) = p
  +rc = R.Fr.to_canonical(r)
  +sc = R.Fr.to_canonical(s)
  +rsc = R.Fr.to_canonical(R.Fr.mul(r, s))
  +dj = G.G1.from_affine(delta)
  +A = G.G1.add_mixed(G.G1.add(G.G1.from_affine(mA), G.G1.mul_scalar(dj, rc)), alpha)
  +B1 = G.G1.add_mixed(G.G1.add(G.G1.from_affine(mB1), G.G1.mul_scalar(dj, sc)), beta)
  +B2 = G2.G2.add_mixed(G2.G2.add(G2.G2.from_affine(mB2), G2.G2.mul_scalar(G2.G2.from_affine(delta2), sc)), beta2)
  +C = G.G1.add(G.G1.add(G.G1.add(G.G1.mul_scalar(A, sc), G.G1.mul_scalar(B1, rc)), G.G1.neg(G.G1.mul_scalar(dj, rsc))), G.G1.from_affine(mLH))
  Out{G.G1.to_affine(A), G2.G2.to_affine(B2), G.G1.to_affine(C)}

def Groth.combine.c8(res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, +beta2: G2.G2Aff, +delta2: G2.G2Aff, +mA: G.G1Aff, +mB1: G.G1Aff, p: Array<U32> & G.G1Aff) -> Out:
  (res1, +mLH) = p
  Groth.combine.c9(r, s, alpha, beta, delta, beta2, delta2, mA, mB1, mLH, G2.G2Aff.from_array(res2, 0n))

def Groth.combine.c7(res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, +beta2: G2.G2Aff, +delta2: G2.G2Aff, +mA: G.G1Aff, p: Array<U32> & G.G1Aff) -> Out:
  (res1, +mB1) = p
  Groth.combine.c8(res2, r, s, alpha, beta, delta, beta2, delta2, mA, mB1, G.G1Aff.from_array(res1, 2n))

def Groth.combine.c6(res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, +beta2: G2.G2Aff, +delta2: G2.G2Aff, p: Array<U32> & G.G1Aff) -> Out:
  (res1, +mA) = p
  Groth.combine.c7(res2, r, s, alpha, beta, delta, beta2, delta2, mA, G.G1Aff.from_array(res1, 1n))

def Groth.combine.c5(res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, +beta2: G2.G2Aff, p: Array<U32> & G2.G2Aff) -> Out:
  (g2, +delta2) = p
  Groth.combine.c6(res2, r, s, alpha, beta, delta, beta2, delta2, G.G1Aff.from_array(res1, 0n))

def Groth.combine.c4(res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, +delta: G.G1Aff, p: Array<U32> & G2.G2Aff) -> Out:
  (g2, +beta2) = p
  Groth.combine.c5(res1, res2, r, s, alpha, beta, delta, beta2, G2.G2Aff.from_array(g2, 1n))

def Groth.combine.c3(g2: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, +beta: G.G1Aff, p: Array<U32> & G.G1Aff) -> Out:
  (g1, +delta) = p
  Groth.combine.c4(res1, res2, r, s, alpha, beta, delta, G2.G2Aff.from_array(g2, 0n))

def Groth.combine.c2(g2: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, +alpha: G.G1Aff, p: Array<U32> & G.G1Aff) -> Out:
  (g1, +beta) = p
  Groth.combine.c3(g2, res1, res2, r, s, alpha, beta, G.G1Aff.from_array(g1, 2n))

def Groth.combine.c1(g2: Array<U32>, res1: Array<U32>, res2: Array<U32>, +r: R.Fr, +s: R.Fr, p: Array<U32> & G.G1Aff) -> Out:
  (g1, +alpha) = p
  Groth.combine.c2(g2, res1, res2, r, s, alpha, G.G1Aff.from_array(g1, 1n))

def Groth.combine(st: S) -> Out:
  S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  Groth.combine.c1(g2, res1, res2, r, s, G.G1Aff.from_array(g1, 0n))
