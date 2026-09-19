# Concrete theorems about the real bend2/src/fr.bend code, checked by `bend`'s
# normalizer: `{==}` holds only when both sides compute to the same term.
# These are not universal statements (no quantifiers) but they do run the actual
# generated limb code inside the type checker.
import Base
import ../src/fr.bend as F

# 2R mod p, 16 x 16-bit little-endian limbs (Montgomery form of 2)
def two() -> F.Fr:
  F.Fr{65526, 40959, 26680, 22828, 39507, 16065, 60715, 28152, 35932, 61682, 18142, 52445, 48734, 13327, 61315, 7188}

# -1 in Montgomery form: p - (R mod p)
def neg_one() -> F.Fr:
  F.Fr{6, 40960, 49527, 38731, 41831, 55896, 29106, 61751, 4654, 2312, 41543, 20961, 49402, 18217, 54961, 8793}

# 1 + 1 = 2 (no modular wrap)
def add_one_one() -> {F.Fr.add(F.Fr.one(), F.Fr.one()) == two() : F.Fr}:
  {==}

# 1 + (-1) = 0 (exercises the conditional-subtract-p path)
def add_one_neg_one() -> {F.Fr.add(F.Fr.one(), neg_one()) == F.Fr.zero() : F.Fr}:
  {==}

# 0 - 1 = -1 (borrow path)
def sub_zero_one() -> {F.Fr.sub(F.Fr.zero(), F.Fr.one()) == neg_one() : F.Fr}:
  {==}

# F.Fr.neg(1) = -1
def neg_one_ok() -> {F.Fr.neg(F.Fr.one()) == neg_one() : F.Fr}:
  {==}

# F.Fr.eq(1, 1) = 1 and F.Fr.is_zero(0) = 1
def eq_refl_one() -> {F.Fr.eq(F.Fr.one(), F.Fr.one()) == 1 : U32}:
  {==}

def is_zero_zero() -> {F.Fr.is_zero(F.Fr.zero()) == 1 : U32}:
  {==}

# Montgomery multiplication: 1 * 1 = 1 and 2 * 1 = 2 (runs the full 16-limb
# CIOS Fr.mul, ~1700 generated lines, inside the checker)
def mul_one_one() -> {F.Fr.mul(F.Fr.one(), F.Fr.one()) == F.Fr.one() : F.Fr}:
  {==}

def mul_two_one() -> {F.Fr.mul(two(), F.Fr.one()) == two() : F.Fr}:
  {==}

# round trip through the canonical (non-Montgomery) representation
def canon_round_trip() -> {F.Fr.to_canonical(F.Fr.from_canonical(F.Fr.raw_one())) == F.Fr.raw_one() : F.Fr}:
  {==}
