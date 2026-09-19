# Groth16 prover entry point (Bend 2). Reads the data directory from $BENDG_DATA
# (bend2/FORMAT.md), prints `A x y` / `B x0 x1 y0 y1` / `C x y` then `T <phase> <ms>` lines.
# Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend bend2/prove.bend -o prove_bin  (bend2/scripts/prove.sh)
import Base
import ./src/msm.bend as Msm
import ./src/ntt.bend as N
import ./src/fr.bend as R
import ./src/g1.bend as G
import ./src/g2.bend as G2
import ./src/bin_io.bend as Io
import ./src/groth16.bend as P

# ---------------------------------------------------------------- GPU dispatch (BENDG_GPU=1 → one `!` per MSM / qap phase)

def Pr.env_gpu.fin(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Done{s}:
      String.eq(s, "1")
    case Fail{e}:
      False{}

def Pr.g1_dev(pts: Array<U32>, scs: Array<U32>, +n: Nat) -> Array<U32> & (Array<U32> & G.G1):
  Msm.g1(pts, scs, n)

def Pr.g1_run(gpu: Bool, pts: Array<U32>, scs: Array<U32>, +n: Nat) -> Array<U32> & (Array<U32> & G.G1):
  match gpu:
    case True{}:
      Pr.g1_dev!(pts, scs, n)
    case False{}:
      Msm.g1(pts, scs, n)

def Pr.g2_dev(pts: Array<U32>, scs: Array<U32>, +n: Nat) -> Array<U32> & (Array<U32> & G2.G2):
  Msm.g2(pts, scs, n)

def Pr.g2_run(gpu: Bool, pts: Array<U32>, scs: Array<U32>, +n: Nat) -> Array<U32> & (Array<U32> & G2.G2):
  match gpu:
    case True{}:
      Pr.g2_dev!(pts, scs, n)
    case False{}:
      Msm.g2(pts, scs, n)

def Pr.qap_dev(a: Array<U32>, b: Array<U32>, c: Array<U32>, +lg: Nat) -> Array<U32>:
  N.Ntt.qap_h(a, b, c, lg)

def Pr.qap_run(gpu: Bool, a: Array<U32>, b: Array<U32>, c: Array<U32>, +lg: Nat) -> Array<U32>:
  match gpu:
    case True{}:
      Pr.qap_dev!(a, b, c, lg)
    case False{}:
      N.Ntt.qap_h(a, b, c, lg)

# ---------------------------------------------------------------- phase: h coefficients (canonical)

def Pr.qap(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, z, zl, ca, cb, cc, P.Groth.empty(), P.Groth.empty(), P.Groth.empty(), P.Sc.canon(U32.to_nat(nh), 0n, Pr.qap_run(gpu, ea, eb, ec, U32.to_nat(lg))), g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s}

def Pr.msm_a.fin(st: P.S, p: Array<U32> & (Array<U32> & G.G1)) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  (pa2, p1) = p
  (z2, m) = p1
  P.S{h, z2, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa2, pb1, pb2, ph, pl, P.Groth.acc_g1(res1, 0n, m), res2, r, s}

def Pr.msm_a(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Pr.msm_a.fin(P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, P.Groth.empty(), zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, P.Groth.empty(), pb1, pb2, ph, pl, res1, res2, r, s}, Pr.g1_run(gpu, pa, z, U32.to_nat(na)))

def Pr.msm_b1.fin(st: P.S, p: Array<U32> & (Array<U32> & G.G1)) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  (pb12, p1) = p
  (z2, m) = p1
  P.S{h, z2, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb12, pb2, ph, pl, P.Groth.acc_g1(res1, 1n, m), res2, r, s}

def Pr.msm_b1(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Pr.msm_b1.fin(P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, P.Groth.empty(), zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, P.Groth.empty(), pb2, ph, pl, res1, res2, r, s}, Pr.g1_run(gpu, pb1, z, U32.to_nat(nb)))

def Pr.msm_b2.fin(st: P.S, p: Array<U32> & (Array<U32> & G2.G2)) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  (pb22, p1) = p
  (z2, m) = p1
  P.S{h, z2, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb22, ph, pl, res1, P.Groth.acc_g2(res2, 0n, m), r, s}

def Pr.msm_b2(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Pr.msm_b2.fin(P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, P.Groth.empty(), zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, P.Groth.empty(), ph, pl, res1, res2, r, s}, Pr.g2_run(gpu, pb2, z, U32.to_nat(nb)))

def Pr.msm_h.fin(st: P.S, p: Array<U32> & (Array<U32> & G.G1)) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  (ph2, p1) = p
  (hh2, m) = p1
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh2, g1, g2, pa, pb1, pb2, ph2, pl, P.Groth.acc_g1(res1, 2n, m), res2, r, s}

def Pr.msm_h(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Pr.msm_h.fin(P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, z, zl, ca, cb, cc, ea, eb, ec, P.Groth.empty(), g1, g2, pa, pb1, pb2, P.Groth.empty(), pl, res1, res2, r, s}, Pr.g1_run(gpu, ph, hh, U32.to_nat(nh)))

def Pr.msm_l.fin(st: P.S, p: Array<U32> & (Array<U32> & G.G1)) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  (pl2, p1) = p
  (zl2, m) = p1
  P.S{h, z, zl2, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl2, P.Groth.acc_g1(res1, 2n, m), res2, r, s}

def Pr.msm_l(gpu: Bool, st: P.S) -> P.S:
  P.S{h, z, zl, ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, pl, res1, res2, r, s} = st
  match h:
    case P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}:
      Pr.msm_l.fin(P.S{P.Hdr{nc, ni, nw, lg, na, nb, nh, nl}, z, P.Groth.empty(), ca, cb, cc, ea, eb, ec, hh, g1, g2, pa, pb1, pb2, ph, P.Groth.empty(), res1, res2, r, s}, Pr.g1_run(gpu, pl, zl, U32.to_nat(nl)))

def Pr.show(o: P.Out) -> IO(Unit):
  match o:
    case P.Out{a, b, c}:
      do IO<Unit>:
        IO.print("A " ++ G.G1.show_affine(a))
        IO.print("B " ++ G2.G2.show_affine(b))
        IO.print("C " ++ G.G1.show_affine(c))

def Pr.t(name: String, +t0: Nat, +t1: Nat) -> IO(Unit):
  IO.print("T " ++ name ++ " " ++ Nat.show(Nat.sub(t1, t0)))

def Pr.run(+dir: String, +gpu: Bool) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    ha : Array<U32> <- Io.load_u32(dir ++ "/header.bin", 3n, 0)
    nza : U32 <- P.Groth.first_word(dir ++ "/r1cs_a.bin")
    nzb : U32 <- P.Groth.first_word(dir ++ "/r1cs_b.bin")
    nzc : U32 <- P.Groth.first_word(dir ++ "/r1cs_c.bin")
    s0 : P.S <- P.Groth.load(dir, P.Hdr.read(ha), nza, nzb, nzc)
    +t1 : Nat <- IO.now()
    s1 : P.S = P.Groth.evals(s0)
    +t2 : Nat <- IO.now()
    s2 : P.S = Pr.qap(gpu, s1)
    +t3 : Nat <- IO.now()
    s3 : P.S = Pr.msm_a(gpu, s2)
    +t4 : Nat <- IO.now()
    s4 : P.S = Pr.msm_b1(gpu, s3)
    +t5 : Nat <- IO.now()
    s5 : P.S = Pr.msm_b2(gpu, s4)
    +t6 : Nat <- IO.now()
    s6 : P.S = Pr.msm_h(gpu, s5)
    +t7 : Nat <- IO.now()
    s7 : P.S = Pr.msm_l(gpu, s6)
    +t8 : Nat <- IO.now()
    Pr.show(P.Groth.combine(s7))
    +t9 : Nat <- IO.now()
    Pr.t("load", t0, t1)
    Pr.t("evals", t1, t2)
    Pr.t("qap", t2, t3)
    Pr.t("msm_a", t3, t4)
    Pr.t("msm_b1", t4, t5)
    Pr.t("msm_b2", t5, t6)
    Pr.t("msm_h", t6, t7)
    Pr.t("msm_l", t7, t8)
    Pr.t("total", t0, t9)

def main() -> IO(Unit):
  do IO<Unit>:
    dir : String <- IO.try(String, IO.get_env("BENDG_DATA"))
    g : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDG_GPU")
    Pr.run(dir, Pr.env_gpu.fin(g))
