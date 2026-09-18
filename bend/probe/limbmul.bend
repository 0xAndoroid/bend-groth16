# Bend 1 cost probe A: 254-bit schoolbook multiply, 12-bit limbs in a little-endian List(u24).
# 22 limbs (264 bits). a*b + carry <= 4095*4095 + 4095 = 16773120 < 2^24: never wraps.
# 2^16 independent multiplies shaped as a binary tree so HVM parallelizes them.
# Run: bend gen-c bend/probe/limbmul.bend > lm.c && clang -O2 -DTPC_L2=3 lm.c -o lm -lm -lpthread && ./lm
def row(a, bs, carry):
  match bs:
    case List/Nil:
      return [carry]
    case List/Cons:
      p = a * bs.head + carry
      return List/Cons(p & 4095, row(a, bs.tail, p >> 12))

def add(xs, ys, carry):
  match xs:
    case List/Nil:
      match ys:
        case List/Nil:
          switch carry:
            case 0:
              return List/Nil
            case _:
              return [carry]
        case List/Cons:
          s = ys.head + carry
          return List/Cons(s & 4095, add(List/Nil, ys.tail, s >> 12))
    case List/Cons:
      match ys:
        case List/Nil:
          s = xs.head + carry
          return List/Cons(s & 4095, add(xs.tail, List/Nil, s >> 12))
        case List/Cons:
          s = xs.head + ys.head + carry
          return List/Cons(s & 4095, add(xs.tail, ys.tail, s >> 12))

def mul(as, bs):
  match as:
    case List/Nil:
      return List/Nil
    case List/Cons:
      return add(row(as.head, bs, 0), List/Cons(0, mul(as.tail, bs)), 0)

# n pseudo-random 12-bit limbs from a seed
def gen(n, seed):
  switch n:
    case 0:
      return List/Nil
    case _:
      return List/Cons((seed * 7919 + n * 104729) & 4095, gen(n-1, seed))

def chk(xs, acc):
  match xs:
    case List/Nil:
      return acc
    case List/Cons:
      return chk(xs.tail, acc * 31 + xs.head)

def many(d, seed):
  switch d:
    case 0:
      return chk(mul(gen(22, seed), gen(22, seed + 1)), 0)
    case _:
      return many(d-1, seed * 2) + many(d-1, seed * 2 + 1)

def main():
  return many(16, 1)
