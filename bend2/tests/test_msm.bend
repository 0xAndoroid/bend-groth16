# Checks Msm.g1 against arkworks vectors data/vectors/bend/msm_small_{8,64,1024}.bin
# (run from the repo root). File: u32 n; n G1 affine; n Fr canonical scalars; result G1.
# Loaded with pad 15 (unit u = file word 16 u - 15 + ...: points start at unit 1); the
# points and scalars are copied into their own arrays so that element i sits at 32 i / 16 i.
import Base
import ../src/g1.bend as G
import ../src/msm.bend as Msm
import ../src/bin_io.bend as Io

# copy k words src[si..] -> dst[di..]; pr = (src, src[si]); returns (src, dst)
def T.copy(k: Nat, +si: U32, +di: U32, dst: Array<U32>, pr: Array<U32> & U32) -> Array<U32> & Array<U32>:
  match k:
    case 0n:
      (src, +w) = pr
      (src, dst)
    case 1n+j:
      (src, +w) = pr
      T.copy(j, (si + 1 : U32), (di + 1 : U32), dst[di] <- w, src[(si + 1 : U32)])

def T.check.s(+exp: G.G1Aff, r: Array<U32> & (Array<U32> & G.G1)) -> U32:
  (pts, rest) = r
  (scs, res) = rest
  G.G1.eq_affine(G.G1.to_affine(res), exp)

def T.check.s3(+n: Nat, pts: Array<U32>, scs: Array<U32>, pr: Array<U32> & G.G1Aff) -> U32:
  (arr, +exp) = pr
  T.check.s(exp, Msm.g1(pts, scs, n))

def T.check.s2(+n: Nat, pts: Array<U32>, pr: Array<U32> & Array<U32>) -> U32:
  (arr, scs) = pr
  T.check.s3(n, pts, scs, G.G1Aff.from_array_at(arr, (1n + (3n * n))))

def T.check.s1(+n: Nat, +d: Nat, pr: Array<U32> & Array<U32>) -> U32:
  (arr, pts) = pr
  +k = U32.from_nat((16n + (32n * n)))
  T.check.s2(n, pts, T.copy((16n * n), k, 0, Array.new(U32, d, 0), arr[k]))

# n points at word 16 (unit 1), n scalars at unit 1 + 2n, result at unit 1 + 3n
def T.check(+n: Nat, +d: Nat, arr: Array<U32>) -> U32:
  T.check.s1(n, d, T.copy((32n * n), 16, 0, Array.new(U32, d, 0), arr[16]))

def T.case(path: String, +n: Nat, +d: Nat) -> IO(U32):
  do IO<U32>:
    arr : Array<U32> <- Io.load_u32(path, d, 15)
    return T.check(n, d, arr)

def T.verdict(ok: Bool, name: String) -> String:
  match ok:
    case True{}:
      "PASS " ++ name
    case False{}:
      "FAIL " ++ name

def main() -> IO(Unit):
  do IO<Unit>:
    +a : U32 <- T.case("data/vectors/bend/msm_small_8.bin", 8n, 9n)
    +b : U32 <- T.case("data/vectors/bend/msm_small_64.bin", 64n, 12n)
    +c : U32 <- T.case("data/vectors/bend/msm_small_1024.bin", 1024n, 16n)
    IO.print(T.verdict(U32.is_eq(a, 1), "msm_small_8") ++ " " ++ T.verdict(U32.is_eq(b, 1), "msm_small_64") ++ " " ++ T.verdict(U32.is_eq(c, 1), "msm_small_1024"))
    IO.print(T.verdict(U32.is_eq(U32.and(U32.and(a, b), c), 1), U32.show(U32.add(U32.add(a, b), c)) ++ "/3"))
