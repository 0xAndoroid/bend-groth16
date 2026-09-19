# A universal (quantified) theorem in the style of the generated limb code:
# a 2-limb, 16-bit-per-U32 carry-propagating add, proven commutative for ALL
# inputs. The proof rewrites each U32.add(ai, bi) into U32.add(bi, ai) with Base's U32.add_comm (itself proven
# by induction on the 32-bit Word bit vector in base.bend), then closes by
# reflexivity. No tactics: each rewrite spells the whole goal with `_` at the
# rewritten spot, so this scales linearly in code size (16 limbs = 16 motives).
import Base

type L2 is Data:
  L2{+l0: U32, +l1: U32}

# same shape as one carry step of bend2/src/fr.bend Fr.add
def add2(a: L2, b: L2) -> L2:
  match a b:
    case L2{a0, a1} L2{b0, b1}:
      +v1 = U32.add(a0, b0)
      +v2 = U32.and(v1, 65535)
      +v3 = U32.shrn(v1, 16n)
      +v4 = U32.add(U32.add(a1, b1), v3)
      +v5 = U32.and(v4, 65535)
      L2{v2, v5}

law add2_comm:
  for a: L2
  for b: L2
  {add2(a, b) == add2(b, a) : L2}

def add2_comm(a, b):
  match a b:
    case L2{a0, a1} L2{b0, b1}:
      %U32.add_comm(b0, a0) : {L2{U32.and(_, 65535), U32.and(U32.add(U32.add(a1, b1), U32.shrn(_, 16n)), 65535)} == add2(L2{b0, b1}, L2{a0, a1}) : L2}
      %U32.add_comm(b1, a1) : {L2{U32.and(U32.add(b0, a0), 65535), U32.and(U32.add(_, U32.shrn(U32.add(b0, a0), 16n)), 65535)} == add2(L2{b0, b1}, L2{a0, a1}) : L2}
      {==}
