# MSM benchmark on real proving-key points: G1 from data/18/bend/pk_a.bin (N <= 18) or
# pk_h.bin (N = 19; N = 20 duplicates the 2^19 pk_h points with different scalars), G2 from
# pk_b2.bin; scalars = canonical witness.bin entries, cycled. Prints ms and the affine
# result (must match across --threads 1 / default / MODE=gpu). Run from the repo root:
#   Build: BEND_NO_TELEMETRY=1 ~/.bend/bin/bend bend2/bench/msm.bend -o msm
#   Run:   MODE=cpu G=1 N=20 [C=12 FD=4] ./msm [--threads 1] ; MODE=gpu N=20 ./msm
# C=0 / FD=99 mean "use the Msm defaults for this n".
import Base
import ../src/fr.bend as R
import ../src/g1.bend as G
import ../src/g2.bend as G2
import ../src/msm.bend as Msm
import ../src/bin_io.bend as Io

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

# scalars[i] = to_canonical(witness[i mod nw]) for i < n; pr = (witness, witness[i mod nw])
def B.scalars(k: Nat, +i: Nat, +nw: Nat, dst: Array<U32>, pr: Array<U32> & R.Fr) -> Array<U32>:
  match k:
    case 0n:
      (w, x) = pr
      dst
    case 1n+j:
      (w, x) = pr
      B.scalars(j, (i + 1n), nw, R.Fr.to_array(dst, i, R.Fr.to_canonical(x)), R.Fr.from_array(w, ((i + 1n) % nw)))

def B.dup(pr: Array<U32> & Array<U32>) -> Array<U32>:
  (a, b) = pr
  ANode{a, b}

def B.points_big(twice: Bool) -> IO(Array<U32>):
  match twice:
    case True{}:
      do IO<Array<U32>>:
        a : Array<U32> <- Io.load_u32("data/18/bend/pk_h.bin", 24n, 0)
        return B.dup(Array.clone(U32, a))
    case False{}:
      Io.load_u32("data/18/bend/pk_h.bin", 24n, 0)

def B.points_g1.fin(small: Bool, +n: Nat) -> IO(Array<U32>):
  match small:
    case True{}:
      Io.load_u32("data/18/bend/pk_a.bin", (n + 5n), 0)
    case False{}:
      B.points_big(Nat.is_eq(n, 20n))

# 2^N point slots: pk_a for N <= 18, pk_h for N = 19, pk_h twice for N = 20
def B.points_g1(+n: Nat) -> IO(Array<U32>):
  B.points_g1.fin(Nat.is_lt(n, 19n), n)

def B.points(g2: Bool, +n: Nat) -> IO(Array<U32>):
  match g2:
    case True{}:
      Io.load_u32("data/18/bend/pk_b2.bin", (n + 6n), 0)
    case False{}:
      B.points_g1(n)

def B.show_g1(r: Array<U32> & (Array<U32> & G.G1)) -> String:
  (pts, rest) = r
  (scs, res) = rest
  G.G1.show_affine(G.G1.to_affine(res))

def B.show_g2(r: Array<U32> & (Array<U32> & G2.G2)) -> String:
  (pts, rest) = r
  (scs, res) = rest
  G2.G2.show_affine(G2.G2.to_affine(res))

def B.g1_gpu(pts: Array<U32>, scs: Array<U32>, +n: Nat, +c: Nat, +fd: Nat) -> Array<U32> & (Array<U32> & G.G1):
  Msm.g1_with(pts, scs, n, c, fd)

def B.g2_gpu(pts: Array<U32>, scs: Array<U32>, +n: Nat, +c: Nat, +fd: Nat) -> Array<U32> & (Array<U32> & G2.G2):
  Msm.g2_with(pts, scs, n, c, fd)

def B.run_g1(gpu: Bool, pts: Array<U32>, scs: Array<U32>, +n: Nat, +c: Nat, +fd: Nat) -> String:
  match gpu:
    case True{}:
      B.show_g1(B.g1_gpu!(pts, scs, n, c, fd))
    case False{}:
      B.show_g1(Msm.g1_with(pts, scs, n, c, fd))

def B.run_g2(gpu: Bool, pts: Array<U32>, scs: Array<U32>, +n: Nat, +c: Nat, +fd: Nat) -> String:
  match gpu:
    case True{}:
      B.show_g2(B.g2_gpu!(pts, scs, n, c, fd))
    case False{}:
      B.show_g2(Msm.g2_with(pts, scs, n, c, fd))

def B.run(g2: Bool, gpu: Bool, pts: Array<U32>, scs: Array<U32>, +n: Nat, +c: Nat, +fd: Nat) -> String:
  match g2:
    case True{}:
      B.run_g2(gpu, pts, scs, n, c, fd)
    case False{}:
      B.run_g1(gpu, pts, scs, n, c, fd)

def B.pick(dflt: Bool, +v: Nat, +d: Nat) -> Nat:
  match dflt:
    case True{}:
      d
    case False{}:
      v

def main() -> IO(Unit):
  do IO<Unit>:
    +mode : String <- env_str("MODE", "cpu")
    +ln : Nat <- env_nat("N", 16n)
    +g : Nat <- env_nat("G", 1n)
    +c0 : Nat <- env_nat("C", 0n)
    +fd0 : Nat <- env_nat("FD", 99n)
    +n : Nat = Nat.pow(2n, ln)
    +c : Nat = B.pick(Nat.is_eq(c0, 0n), c0, Msm.Msm.pick_c(n))
    +fd : Nat = B.pick(Nat.is_eq(fd0, 99n), fd0, Msm.Msm.pick_fd(n, c))
    +g2 : Bool = Nat.is_eq(g, 2n)
    pts : Array<U32> <- B.points(g2, ln)
    w : Array<U32> <- Io.load_u32("data/18/bend/witness.bin", 22n, 0)
    scs : Array<U32> = B.scalars(n, 0n, (Nat.pow(2n, 18n) + 2n), Array.new(U32, (ln + 4n), 0), R.Fr.from_array(w, 0n))
    t0 : Nat <- IO.now()
    +res : String = B.run(g2, String.eq(mode, "gpu"), pts, scs, n, c, fd)
    t1 : Nat <- IO.now()
    IO.print("msm g" ++ Nat.show(g) ++ " N=" ++ Nat.show(ln) ++ " c=" ++ Nat.show(c) ++ " fd=" ++ Nat.show(fd) ++ " mode=" ++ mode ++ " ms=" ++ Nat.show(Nat.sub(t1, t0)) ++ " res=" ++ res)
