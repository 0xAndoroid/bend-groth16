"""Emit bend2/src/{fr,fq}.bend: BN254 prime-field arithmetic for Bend 2 with 16 x 16-bit
limbs held in U32 (the only native integer: no U64, no mul-hi, wrapping mul). One CIOS
cell t + a*b + c <= (2^16-1)^2 + 2*(2^16-1) = 2^32-1 is exact in U32. Montgomery form,
R = 2^256, exactly the bend2/FORMAT.md representation. Generalises bend2/probe/gen_montmul.py.
Also emits bend2/tests/test_{fr,fq}.bend (vector checks against data/vectors/bend/*_ops.bin).
Run: uv run python bend2/gen/gen_field.py
"""
from pathlib import Path

L = 16
MASK = (1 << 16) - 1
FIELDS = {
    "Fr": 21888242871839275222246405745257275088548364400416034343698204186575808495617,
    "Fq": 21888242871839275222246405745257275088696311157297823662689037894645226208583,
}
ROOT = Path(__file__).resolve().parents[2]


def to_limbs(x):
    return [(x >> (16 * j)) & MASK for j in range(L)]


class Gen:
    def __init__(self, name, p):
        self.N = name
        self.P = p
        self.pl = to_limbs(p)
        self.n0 = (-pow(p, -1, 1 << 16)) % (1 << 16)
        self.out = []
        self.fresh = 0

    def w(self, s=""):
        self.out.append(s)

    def rec(self, prefix):
        return "%s{%s}" % (self.N, ", ".join("%s%d" % (prefix, j) for j in range(L)))

    def lit(self, x):
        return "%s{%s}" % (self.N, ", ".join(str(v) for v in to_limbs(x)))

    # ---- SSA helpers: each cell is one `+v = expr` line at indent 6 ----
    def emit(self, expr):
        self.fresh += 1
        v = "v%d" % self.fresh
        self.w("      +%s = %s" % (v, expr))
        return v

    def cond_sub_p(self, t, carry):
        """r = t - p if t >= p (incl. a 2^256 carry) else t; branch-free select."""
        d, br = [], None
        for j in range(L):
            s = "U32.sub(U32.add(%s, 65536), %d)" % (t[j], self.pl[j])
            if br is not None:
                s = "U32.sub(%s, %s)" % (s, br)
            s = self.emit(s)
            d.append(self.emit("U32.and(%s, 65535)" % s))
            br = self.emit("U32.sub(1, U32.shrn(%s, 16n))" % s)
        ge = self.emit("U32.or(%s, U32.sub(1, %s))" % (carry, br))
        keep = self.emit("U32.sub(%s, 1)" % ge)  # 0xFFFFFFFF when t < p
        r = [self.emit("U32.or(U32.and(%s, %s), U32.and(%s, U32.not(%s)))" % (t[j], keep, d[j], keep)) for j in range(L)]
        self.w("      %s{%s}" % (self.N, ", ".join(r)))

    def head2(self, name, a="a", b="b"):
        N = self.N
        self.w("def %s.%s(%s: %s, %s: %s) -> %s:" % (N, name, a, N, b, N, N))
        self.w("  match %s %s:" % (a, b))
        self.w("    case %s %s:" % (self.rec(a), self.rec(b)))

    # ---- ops ----
    def gen_add(self):
        self.head2("add")
        t, c = [], None
        for j in range(L):
            s = "U32.add(a%d, b%d)" % (j, j)
            if c is not None:
                s = "U32.add(%s, %s)" % (s, c)
            s = self.emit(s)
            t.append(self.emit("U32.and(%s, 65535)" % s))
            c = self.emit("U32.shrn(%s, 16n)" % s)
        self.cond_sub_p(t, c)
        self.w()

    def gen_sub(self):
        self.head2("sub")
        d, br = [], None
        for j in range(L):
            s = "U32.sub(U32.add(a%d, 65536), b%d)" % (j, j)
            if br is not None:
                s = "U32.sub(%s, %s)" % (s, br)
            s = self.emit(s)
            d.append(self.emit("U32.and(%s, 65535)" % s))
            br = self.emit("U32.sub(1, U32.shrn(%s, 16n))" % s)
        # e = d + p (used when a < b, i.e. final borrow = 1)
        e, c = [], None
        for j in range(L):
            s = "U32.add(%s, %d)" % (d[j], self.pl[j])
            if c is not None:
                s = "U32.add(%s, %s)" % (s, c)
            s = self.emit(s)
            e.append(self.emit("U32.and(%s, 65535)" % s))
            c = self.emit("U32.shrn(%s, 16n)" % s)
        m = self.emit("U32.sub(0, %s)" % br)  # 0xFFFFFFFF when borrow
        r = [self.emit("U32.or(U32.and(%s, %s), U32.and(%s, U32.not(%s)))" % (e[j], m, d[j], m)) for j in range(L)]
        self.w("      %s{%s}" % (self.N, ", ".join(r)))
        self.w()

    def gen_mul(self):
        self.head2("mul")
        e = self.emit
        t = ["0"] * (L + 2)
        for i in range(L):
            c = None
            for j in range(L):
                prod = "U32.mul(a%d, b%d)" % (j, i)
                s = "U32.add(%s, %s)" % (t[j], prod) if t[j] != "0" else prod
                if c is not None:
                    s = "U32.add(%s, %s)" % (s, c)
                s = e(s)
                t[j] = e("U32.and(%s, 65535)" % s)
                c = e("U32.shrn(%s, 16n)" % s)
            s = e("U32.add(%s, %s)" % (t[L], c)) if t[L] != "0" else c
            t[L] = e("U32.and(%s, 65535)" % s)
            t[L + 1] = e("U32.shrn(%s, 16n)" % s)
            m = e("U32.and(U32.mul(%s, %d), 65535)" % (t[0], self.n0))
            s = e("U32.add(%s, U32.mul(%s, %d))" % (t[0], m, self.pl[0]))
            c = e("U32.shrn(%s, 16n)" % s)
            for j in range(1, L):
                s = e("U32.add(U32.add(%s, U32.mul(%s, %d)), %s)" % (t[j], m, self.pl[j], c))
                t[j - 1] = e("U32.and(%s, 65535)" % s)
                c = e("U32.shrn(%s, 16n)" % s)
            s = e("U32.add(%s, %s)" % (t[L], c))
            t[L - 1] = e("U32.and(%s, 65535)" % s)
            c = e("U32.shrn(%s, 16n)" % s)
            t[L] = e("U32.add(%s, %s)" % (t[L + 1], c))
            t[L + 1] = "0"
        self.cond_sub_p(t[:L], t[L])
        self.w()

    def gen_inv(self):
        """a^(p-2) by left-to-right square-and-multiply, fully unrolled."""
        N = self.N
        e = self.P - 2
        bits = bin(e)[2:]
        self.w("# Fermat inverse: a^(p-2), %d squarings + %d multiplications; inv(0) = 0" % (len(bits) - 1, bits.count("1") - 1))
        self.w("def %s.inv(+a: %s) -> %s:" % (N, N, N))
        acc = "a"
        k = 0
        for bit in bits[1:]:
            k += 1
            self.w("  +x%d = %s.sqr(%s)" % (k, N, acc))
            acc = "x%d" % k
            if bit == "1":
                k += 1
                self.w("  +x%d = %s.mul(%s, a)" % (k, N, acc))
                acc = "x%d" % k
        self.w("  %s" % acc)
        self.w()

    def gen_from_array(self):
        N = self.N
        self.w("# load element i (16 words at 16*i); stage defs open the (array, word) pairs")
        # stages are declared last-to-first (defs must precede their uses)
        for s in range(L - 1, -1, -1):
            vs = ", ".join("+v%d: U32" % j for j in range(s))
            params = "+k: U32, " + (vs + ", " if vs else "") + "p: Array<U32> & U32"
            self.w("def %s.from_array.s%d(%s) -> Array<U32> & %s:" % (N, s, params, N))
            self.w("  (a, +v%d) = p" % s)
            if s == L - 1:
                self.w("  (a, %s{%s})" % (N, ", ".join("v%d" % j for j in range(L))))
            else:
                args = ", ".join(["k"] + ["v%d" % j for j in range(s + 1)])
                self.w("  %s.from_array.s%d(%s, a[(k + %d : U32)])" % (N, s + 1, args, s + 1))
            self.w()
        self.w("def %s.from_array(a: Array<U32>, i: Nat) -> Array<U32> & %s:" % (N, N))
        self.w("  +k = U32.from_nat((i * 16n))")
        self.w("  %s.from_array.s0(k, a[k])" % N)
        self.w()

    def gen_to_array(self):
        N = self.N
        self.w("# store x as element i (16 words at 16*i)")
        self.w("def %s.to_array(a: Array<U32>, i: Nat, x: %s) -> Array<U32>:" % (N, N))
        self.w("  match x:")
        self.w("    case %s:" % self.rec("l"))
        self.w("      +k = U32.from_nat((i * 16n))")
        self.w("      a[k] <- l0")
        for j in range(1, L):
            self.w("      a[(k + %d : U32)] <- l%d" % (j, j))
        self.w("      a")
        self.w()

    def gen(self):
        N = self.N
        w = self.w
        w("# GENERATED by bend2/gen/gen_field.py -- do not edit by hand.")
        w("# BN254 %s: p = %d" % (N, self.P))
        w("# 16 x 16-bit little-endian limbs in U32, Montgomery form with R = 2^256 (bend2/FORMAT.md).")
        w("# n0' = -p^-1 mod 2^16 = %d" % self.n0)
        w("import Base")
        w()
        w("type %s is Data:" % N)
        w("  %s{%s}" % (N, ", ".join("+l%d: U32" % j for j in range(L))))
        w()
        w("def %s.zero() -> %s:" % (N, N))
        w("  %s" % self.lit(0))
        w()
        w("# Montgomery 1 = R mod p")
        w("def %s.one() -> %s:" % (N, N))
        w("  %s" % self.lit((1 << 256) % self.P))
        w()
        w("# R^2 mod p (from_canonical multiplier)")
        w("def %s.r2() -> %s:" % (N, N))
        w("  %s" % self.lit((1 << 512) % self.P))
        w()
        w("# the raw integer 1, NOT in Montgomery form (to_canonical multiplier)")
        w("def %s.raw_one() -> %s:" % (N, N))
        w("  %s" % self.lit(1))
        w()
        w("def %s.modulus() -> %s:" % (N, N))
        w("  %s" % self.lit(self.P))
        w()
        self.gen_add()
        self.gen_sub()
        w("def %s.neg(a: %s) -> %s:" % (N, N, N))
        w("  %s.sub(%s.zero(), a)" % (N, N))
        w()
        w("# Montgomery product a*b*R^-1 mod p (CIOS, 16 rounds, fully unrolled)")
        self.gen_mul()
        w("def %s.sqr(+a: %s) -> %s:" % (N, N, N))
        w("  %s.mul(a, a)" % N)
        w()
        self.gen_inv()
        w("# 1 when x == 0 else 0 (branch-free)")
        w("def %s.is_zero(x: %s) -> U32:" % (N, N))
        w("  match x:")
        w("    case %s:" % self.rec("l"))
        w("      +o = %s" % self.fold_or(["l%d" % j for j in range(L)]))
        w("      U32.sub(1, U32.shrn(U32.or(o, U32.sub(0, o)), 31n))")
        w()
        w("def %s.eq(a: %s, b: %s) -> U32:" % (N, N, N))
        w("  match a b:")
        w("    case %s %s:" % (self.rec("a"), self.rec("b")))
        w("      +o = %s" % self.fold_or(["U32.xor(a%d, b%d)" % (j, j) for j in range(L)]))
        w("      U32.sub(1, U32.shrn(U32.or(o, U32.sub(0, o)), 31n))")
        w()
        w("# raw integer record -> Montgomery form (x * R^2 * R^-1 = x*R)")
        w("def %s.from_canonical(x: %s) -> %s:" % (N, N, N))
        w("  %s.mul(x, %s.r2())" % (N, N))
        w()
        w("# Montgomery form -> raw integer record (x*R * 1 * R^-1 = x)")
        w("def %s.to_canonical(x: %s) -> %s:" % (N, N, N))
        w("  %s.mul(x, %s.raw_one())" % (N, N))
        w()
        self.gen_from_array()
        self.gen_to_array()
        w("# limb 0 (x mod 2^16); handy for checksums")
        w("def %s.lo(x: %s) -> U32:" % (N, N))
        w("  match x:")
        w("    case %s:" % self.rec("l"))
        w("      l0")
        w()
        w("# drop limb 0, shift the rest down, top limb becomes 0")
        w("def %s.shift_down(x: %s) -> %s:" % (N, N, N))
        w("  match x:")
        w("    case %s:" % self.rec("l"))
        w("      %s{%s, 0}" % (N, ", ".join("l%d" % j for j in range(1, L))))
        w()
        w("# limb j of x (0 for j >= 16)")
        w("def %s.limb(j: Nat, x: %s) -> U32:" % (N, N))
        w("  match j:")
        w("    case 0n:")
        w("      %s.lo(x)" % N)
        w("    case 1n+p:")
        w("      %s.limb(p, %s.shift_down(x))" % (N, N))
        w()
        w("# bits lo..lo+width-1 of a CANONICAL (non-Montgomery) x as a U32; width <= 16")
        w("def %s.bits_window(+x: %s, +lo: Nat, width: Nat) -> U32:" % (N, N))
        w("  +q = (lo / 16n)")
        w("  +r = (lo % 16n)")
        w("  +wlo = U32.shrn(%s.limb(q, x), r)" % N)
        w("  +whi = U32.shln(%s.limb((q + 1n), x), Nat.sub(16n, r))" % N)
        w("  U32.and(U32.or(wlo, whi), U32.sub(U32.shln(1, width), 1))")
        w()
        w("def %s.hexc(+n: U32) -> Char:" % N)
        w("  Chr{U32.add(U32.add(n, 48), U32.mul(39, U32.shrn(U32.add(n, 6), 4n)))}")
        w()
        w("def %s.hex4(+v: U32) -> String:" % N)
        w("  SCon{%s.hexc(U32.and(U32.shrn(v, 12n), 15)), SCon{%s.hexc(U32.and(U32.shrn(v, 8n), 15)), SCon{%s.hexc(U32.and(U32.shrn(v, 4n), 15)), SCon{%s.hexc(U32.and(v, 15)), SNil{}}}}}" % (N, N, N, N))
        w()
        w("# 0x + 64 big-endian hex digits of the raw integer record x (call on %s.to_canonical(x))" % N)
        w("def %s.show_raw(x: %s) -> String:" % (N, N))
        w("  match x:")
        w("    case %s:" % self.rec("l"))
        w("      \"0x\" ++ %s" % " ++ ".join("%s.hex4(l%d)" % (N, j) for j in range(L - 1, -1, -1)))
        w()
        w("# canonical big-endian 0x hex of a Montgomery-form x")
        w("def %s.show(x: %s) -> String:" % (N, N))
        w("  %s.show_raw(%s.to_canonical(x))" % (N, N))
        w()
        return "\n".join(self.out)

    def fold_or(self, xs):
        acc = xs[0]
        for x in xs[1:]:
            acc = "U32.or(%s, %s)" % (acc, x)
        return acc


OPS = ["add", "sub", "mul", "neg", "inv", "sqr", "from_canonical", "to_canonical"]


def gen_test(N):
    """test_<n>.bend: per case 9 elements a b add sub mul neg inv sq a_canonical (FORMAT.md)."""
    n = N.lower()
    o = []
    w = lambda s="": o.append(s)
    w("# GENERATED by bend2/gen/gen_field.py -- do not edit by hand.")
    w("# Checks %s ops against arkworks vectors: data/vectors/bend/%s_ops.bin (run from the repo root)." % (N, n))
    w("import Base")
    w("import ../src/%s.bend as F" % n)
    w("import ../src/bin_io.bend as Io")
    w()
    names = ["a", "b", "add", "sub", "mul", "neg", "inv", "sq", "can"]
    # stage chain: T.s0(c, p) ... T.s8(c, a, b, ..., p) -> Array<U32> & U32 (failure bitmask)
    for s in range(8, -1, -1):
        prev = ", ".join("+%s: F.%s" % (names[j], N) for j in range(s))
        w("def T.s%d(+c: Nat, %sp: Array<U32> & F.%s) -> Array<U32> & U32:" % (s, prev + ", " if prev else "", N))
        w("  (arr, +%s) = p" % names[s])
        if s < 8:
            args = ", ".join(["c"] + names[: s + 1])
            w("  T.s%d(%s, F.%s.from_array(arr, (1n + (c * 9n) + %dn)))" % (s + 1, args, N, s + 1))
        else:
            checks = [
                "F.%s.eq(F.%s.add(a, b), add)",
                "F.%s.eq(F.%s.sub(a, b), sub)",
                "F.%s.eq(F.%s.mul(a, b), mul)",
                "F.%s.eq(F.%s.neg(a), neg)",
                "F.%s.eq(F.%s.inv(a), inv)",
                "F.%s.eq(F.%s.sqr(a), sq)",
                "F.%s.eq(F.%s.from_canonical(can), a)",
                "F.%s.eq(F.%s.to_canonical(a), can)",
            ]
            for i, ch in enumerate(checks):
                w("  +ok%d = %s" % (i, ch % (N, N)))
            # bit i set when check i failed
            terms = ["U32.shln(U32.sub(1, ok%d), %dn)" % (i, i) for i in range(len(checks))]
            acc = terms[0]
            for t in terms[1:]:
                acc = "U32.or(%s, %s)" % (acc, t)
            w("  (arr, %s)" % acc)
        w()
    w("def T.check(+c: Nat, arr: Array<U32>) -> Array<U32> & U32:")
    w("  T.s0(c, F.%s.from_array(arr, (1n + (c * 9n))))" % N)
    w()
    w("# 0xFFFFFFFF when m != 0 else 0")
    w("def T.nz(+m: U32) -> U32:")
    w("  U32.sub(0, U32.shrn(U32.or(m, U32.sub(0, m)), 31n))")
    w()
    w("# first = first failure code (case << 8 | opmask), kept once set")
    w("def T.first(+c: U32, +first: U32, +m: U32) -> U32:")
    w("  U32.or(first, U32.and(U32.and(U32.not(T.nz(first)), T.nz(m)), U32.or(U32.shln(c, 8n), m)))")
    w()
    w("# fold the result of case c-1 (r), then check case c; returns fails << 16 | first")
    w("def T.loop(n: Nat, +c: Nat, +fails: U32, +first: U32, r: Array<U32> & U32) -> U32:")
    w("  match n:")
    w("    case 0n:")
    w("      (arr, +m) = r")
    w("      U32.or(U32.shln(U32.add(fails, U32.and(T.nz(m), 1)), 16n), T.first(U32.from_nat(Nat.sub(c, 1n)), first, m))")
    w("    case 1n+p:")
    w("      (arr, +m) = r")
    w("      T.loop(p, (c + 1n), U32.add(fails, U32.and(T.nz(m), 1)), T.first(U32.from_nat(Nat.sub(c, 1n)), first, m), T.check(c, arr))")
    w()
    w("def T.opname(on: Bool, name: String) -> String:")
    w("  match on:")
    w("    case True{}:")
    w("      name ++ \" \"")
    w("    case False{}:")
    w("      \"\"")
    w()
    w("def T.opnames(+m: U32) -> String:")
    w("  " + " ++ ".join("T.opname(U32.is_eq(U32.and(U32.shrn(m, %dn), 1), 1), \"%s\")" % (i, op) for i, op in enumerate(OPS)))
    w()
    w("def T.report(ok: Bool, +code: U32, +cnt: U32) -> String:")
    w("  match ok:")
    w("    case True{}:")
    w("      \"PASS \" ++ U32.show(cnt)")
    w("    case False{}:")
    w("      \"FAIL \" ++ U32.show(U32.shrn(U32.and(code, 65535), 8n)) ++ \" \" ++ T.opnames(U32.and(code, 255)) ++ \"(\" ++ U32.show(U32.shrn(code, 16n)) ++ \" of \" ++ U32.show(cnt) ++ \" cases failing)\"")
    w()
    w("def T.run(r: Array<U32> & U32) -> IO(Unit):")
    w("  (arr, +cnt) = r")
    w("  +code = T.loop(U32.to_nat(cnt), 0n, 0, 0, (arr, 0))")
    w("  IO.print(T.report(U32.is_eq(U32.shrn(code, 16n), 0), code, cnt))")
    w()
    w("def main() -> IO(Unit):")
    w("  do IO<Unit>:")
    w("    arr : Array<U32> <- Io.load_u32(\"data/vectors/bend/%s_ops.bin\", 14n, 15)" % n)
    w("    T.run(arr[15])")
    w()
    return "\n".join(o)


if __name__ == "__main__":
    for name, p in FIELDS.items():
        src = ROOT / "bend2" / "src" / ("%s.bend" % name.lower())
        src.write_text(Gen(name, p).gen())
        tst = ROOT / "bend2" / "tests" / ("test_%s.bend" % name.lower())
        tst.write_text(gen_test(name))
        print("wrote", src, tst)
