"""Emit the NTT constants block of bend2/src/ntt.bend (between the GENERATED markers):
BN254 Fr 2-adic root of unity, its inverse, the coset generator 5, its inverse and 2^-1,
all as Montgomery-form (R = 2^256) 16 x 16-bit U32 limb records (bend2/FORMAT.md).
Run: uv run python bend2/gen/gen_ntt.py
"""
from pathlib import Path

P = 21888242871839275222246405745257275088548364400416034343698204186575808495617
ROOT = 19103219067921713944291392827692070036145651957329286315305642004821462161904  # 2-adicity 28
GEN = 5
R = 1 << 256
ROOT_PATH = Path(__file__).resolve().parents[2] / "bend2" / "src" / "ntt.bend"
BEGIN, END = "# BEGIN GENERATED (bend2/gen/gen_ntt.py)", "# END GENERATED"


def lit(x):
    m = x * R % P
    return "F.Fr{%s}" % ", ".join(str((m >> (16 * j)) & 0xFFFF) for j in range(16))


assert pow(ROOT, 1 << 28, P) == 1 and pow(ROOT, 1 << 27, P) != 1
consts = [
    ("Ntt.root", "TWO_ADIC_ROOT_OF_UNITY (order 2^28)", ROOT),
    ("Ntt.root_inv", "its inverse", pow(ROOT, -1, P)),
    ("Ntt.gen", "coset generator g = Fr::GENERATOR = 5", GEN),
    ("Ntt.gen_inv", "g^-1", pow(GEN, -1, P)),
    ("Ntt.two_inv", "2^-1 (n^-1 = two_inv^log2)", pow(2, -1, P)),
]
block = [BEGIN]
for name, doc, x in consts:
    block += ["# %s (Montgomery)" % doc, "def %s() -> F.Fr:" % name, "  " + lit(x), ""]
block.append(END)
src = ROOT_PATH.read_text()
i, j = src.index(BEGIN), src.index(END) + len(END)
ROOT_PATH.write_text(src[:i] + "\n".join(block) + src[j:])
print("wrote", ROOT_PATH)
