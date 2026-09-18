"""Stdlib reference for Ntt.qap_h: ark-groth16 LibsnarkReduction::witness_map_from_matrices.
Reads data/<K>/{r1cs,witness,pk}.json, builds the A/B/C evaluation vectors over the domain of
size d = pk.domain_size (row i < num_constraints = <row_i, z>; a[num_constraints + i] = z[i]
for the num_instance inputs; zeros elsewhere), computes
  h = coset_ifft( (coset_fft(ifft(a)) * coset_fft(ifft(b)) - coset_fft(ifft(c))) / (g^d - 1) )
with g = Fr::GENERATOR = 5 and arkworks' radix-2 domain, and writes (bend2/FORMAT.md layout,
Montgomery form, 16 x 16-bit limbs as little-endian u32 words)
  data/<K>/bend/abc_evals.bin  (3 d Fr: a | b | c)      data/<K>/bend/h_ref.bin  (d Fr)
Run: uv run python bend2/gen/ref_qap.py data/4
"""
import json
import random
import struct
import sys
from pathlib import Path

P = 21888242871839275222246405745257275088548364400416034343698204186575808495617
ROOT = 19103219067921713944291392827692070036145651957329286315305642004821462161904
GEN = 5
R = 1 << 256


def omega(log2):
    return pow(ROOT, 1 << (28 - log2), P)


def fft(a, w):
    """natural-order in/out radix-2 DIT; w = generator of the size-len(a) domain."""
    n = len(a)
    a = list(a)
    j = 0
    for i in range(1, n):  # bit reversal
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    m = 1
    while m < n:
        wm = pow(w, n // (2 * m), P)
        for k in range(0, n, 2 * m):
            t = 1
            for j in range(m):
                u, v = a[k + j], a[k + j + m] * t % P
                a[k + j], a[k + j + m] = (u + v) % P, (u - v) % P
                t = t * wm % P
        m *= 2
    return a


def ifft(a, log2):
    n = len(a)
    ninv = pow(n, -1, P)
    return [x * ninv % P for x in fft(a, pow(omega(log2), -1, P))]


def coset_fft(a, log2):
    return fft([x * pow(GEN, j, P) % P for j, x in enumerate(a)], omega(log2))


def coset_ifft(a, log2):
    ginv = pow(GEN, -1, P)
    return [x * pow(ginv, j, P) % P for j, x in enumerate(ifft(a, log2))]


def qap_h(a, b, c, log2):
    d = 1 << log2
    a, b, c = (coset_fft(ifft(v, log2), log2) for v in (a, b, c))
    zinv = pow((pow(GEN, d, P) - 1) % P, -1, P)
    return coset_ifft([(x * y - z) % P * zinv % P for x, y, z in zip(a, b, c)], log2)


def evaluate(row, z):
    return sum(int(coeff, 16) * z[col] for col, coeff in row) % P


def to_words(x):
    m = x * R % P
    return [(m >> (16 * j)) & 0xFFFF for j in range(16)]


def write_bin(path, elems):
    words = [w for x in elems for w in to_words(x)]
    path.write_bytes(struct.pack("<%dI" % len(words), *words))


def poly_eval(coeffs, x):
    acc = 0
    for c in reversed(coeffs):
        acc = (acc * x + c) % P
    return acc


def main(dir_):
    dir_ = Path(dir_)
    r1cs = json.loads((dir_ / "r1cs.json").read_text())
    z = [int(v, 16) for v in json.loads((dir_ / "witness.json").read_text())["z"]]
    d = json.loads((dir_ / "pk.json").read_text())["domain_size"]
    log2 = d.bit_length() - 1
    assert 1 << log2 == d
    n, ni = r1cs["num_constraints"], r1cs["num_instance"]
    assert n + ni <= d and len(z) == ni + r1cs["num_witness"]
    a = [evaluate(r, z) for r in r1cs["a"]] + z[:ni] + [0] * (d - n - ni)
    b = [evaluate(r, z) for r in r1cs["b"]] + [0] * (d - n)
    c = [evaluate(r, z) for r in r1cs["c"]] + [0] * (d - n)
    assert all(x * y % P == w for x, y, w in zip(a[:n], b[:n], c[:n])), "witness does not satisfy the R1CS"
    h = qap_h(a, b, c, log2)
    # sanity: A(x) B(x) - C(x) == h(x) (x^d - 1) at a random point, deg h <= d - 2
    x = random.randrange(P)
    pa, pb, pc = (poly_eval(ifft(v, log2), x) for v in (a, b, c))
    assert (pa * pb - pc) % P == poly_eval(h, x) * (pow(x, d, P) - 1) % P
    assert h[-1] == 0
    out = dir_ / "bend"
    out.mkdir(exist_ok=True)
    write_bin(out / "abc_evals.bin", a + b + c)
    write_bin(out / "h_ref.bin", h)
    print("%s: d=2^%d num_constraints=%d num_instance=%d -> %s, %s" % (dir_, log2, n, ni, out / "abc_evals.bin", out / "h_ref.bin"))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/4")
