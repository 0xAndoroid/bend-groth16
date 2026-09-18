# BN254 Fq2 = Fq[u]/(u^2 + 1): Fq2{c0, c1} = c0 + c1*u, components in Montgomery form.
# Layout at rest: c0 then c1 (32 words per element, bend2/FORMAT.md).
import Base
import ./fq.bend as Q

type Fq2 is Data:
  Fq2{+c0: Q.Fq, +c1: Q.Fq}

def Fq2.zero() -> Fq2:
  Fq2{Q.Fq.zero(), Q.Fq.zero()}

def Fq2.one() -> Fq2:
  Fq2{Q.Fq.one(), Q.Fq.zero()}

def Fq2.add(a: Fq2, b: Fq2) -> Fq2:
  match a b:
    case Fq2{a0, a1} Fq2{b0, b1}:
      Fq2{Q.Fq.add(a0, b0), Q.Fq.add(a1, b1)}

def Fq2.sub(a: Fq2, b: Fq2) -> Fq2:
  match a b:
    case Fq2{a0, a1} Fq2{b0, b1}:
      Fq2{Q.Fq.sub(a0, b0), Q.Fq.sub(a1, b1)}

def Fq2.neg(a: Fq2) -> Fq2:
  match a:
    case Fq2{a0, a1}:
      Fq2{Q.Fq.neg(a0), Q.Fq.neg(a1)}

# Karatsuba, 3 Fq muls: (a0 + a1 u)(b0 + b1 u) = (a0 b0 - a1 b1) + ((a0 + a1)(b0 + b1) - a0 b0 - a1 b1) u
def Fq2.mul(a: Fq2, b: Fq2) -> Fq2:
  match a b:
    case Fq2{a0, a1} Fq2{b0, b1}:
      +t0 = Q.Fq.mul(a0, b0)
      +t1 = Q.Fq.mul(a1, b1)
      +t2 = Q.Fq.mul(Q.Fq.add(a0, a1), Q.Fq.add(b0, b1))
      Fq2{Q.Fq.sub(t0, t1), Q.Fq.sub(Q.Fq.sub(t2, t0), t1)}

# (a0 + a1 u)^2 = (a0 + a1)(a0 - a1) + 2 a0 a1 u
def Fq2.sqr(a: Fq2) -> Fq2:
  match a:
    case Fq2{a0, a1}:
      Fq2{Q.Fq.mul(Q.Fq.add(a0, a1), Q.Fq.sub(a0, a1)), Q.Fq.mul(Q.Fq.add(a0, a0), a1)}

# 1/(a0 + a1 u) = (a0 - a1 u) / (a0^2 + a1^2); inv(0) = 0
def Fq2.inv(a: Fq2) -> Fq2:
  match a:
    case Fq2{a0, a1}:
      +ni = Q.Fq.inv(Q.Fq.add(Q.Fq.sqr(a0), Q.Fq.sqr(a1)))
      Fq2{Q.Fq.mul(a0, ni), Q.Fq.neg(Q.Fq.mul(a1, ni))}

def Fq2.is_zero(a: Fq2) -> U32:
  match a:
    case Fq2{a0, a1}:
      U32.and(Q.Fq.is_zero(a0), Q.Fq.is_zero(a1))

def Fq2.eq(a: Fq2, b: Fq2) -> U32:
  match a b:
    case Fq2{a0, a1} Fq2{b0, b1}:
      U32.and(Q.Fq.eq(a0, b0), Q.Fq.eq(a1, b1))

def Fq2.from_array_at.s2(+c0: Q.Fq, p: Array<U32> & Q.Fq) -> Array<U32> & Fq2:
  (a, +c1) = p
  (a, Fq2{c0, c1})

def Fq2.from_array_at.s1(+u: Nat, p: Array<U32> & Q.Fq) -> Array<U32> & Fq2:
  (a, +c0) = p
  Fq2.from_array_at.s2(c0, Q.Fq.from_array(a, (u + 1n)))

# load the Fq2 whose c0 is Fq element u (32 words at word 16*u)
def Fq2.from_array_at(a: Array<U32>, +u: Nat) -> Array<U32> & Fq2:
  Fq2.from_array_at.s1(u, Q.Fq.from_array(a, u))

# load element i (32 words at 32*i)
def Fq2.from_array(a: Array<U32>, i: Nat) -> Array<U32> & Fq2:
  Fq2.from_array_at(a, (i * 2n))

# store x as element i (32 words at 32*i)
def Fq2.to_array(a: Array<U32>, +i: Nat, x: Fq2) -> Array<U32>:
  match x:
    case Fq2{c0, c1}:
      Q.Fq.to_array(Q.Fq.to_array(a, (i * 2n), c0), ((i * 2n) + 1n), c1)

# "c0_hex c1_hex", canonical
def Fq2.show(x: Fq2) -> String:
  match x:
    case Fq2{c0, c1}:
      Q.Fq.show(c0) ++ " " ++ Q.Fq.show(c1)
