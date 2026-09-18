"""Print the Fr constants naive.bend needs as Montgomery-form 16-bit-limb Fr literals.

Usage: uv run python bend2/scripts/gen_naive_consts.py [data/vectors/bend/ntt_small_8.bin]
With a vector file it also checks that omega_k = ROOT^(2^(28-k)) matches arkworks' domain generator.
"""
import struct
import sys

P = 21888242871839275222246405745257275088548364400416034343698204186575808495617
R = 1 << 256
ROOT = 19103219067921713944291392827692070036145651957329286315305642004821462161904


def limbs(x):
    m = x * R % P
    return "Fr{" + ", ".join(str((m >> (16 * i)) & 0xFFFF) for i in range(16)) + "}"


def from_words(ws):
    x = sum(w << (16 * i) for i, w in enumerate(ws))
    return x * pow(R, -1, P) % P


print("# TWO_ADIC_ROOT_OF_UNITY (Montgomery)\n" + limbs(ROOT))
if len(sys.argv) > 1:
    b = open(sys.argv[1], "rb").read()
    n = struct.unpack_from("<I", b, 0)[0]
    omega = from_words(struct.unpack_from("<16I", b, 4))
    k = n.bit_length() - 1
    want = pow(ROOT, 1 << (28 - k), P)
    print(f"n={n} omega_ok={omega == want}")
