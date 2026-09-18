# Bend 1 cost probe B: 256-bit multiply, 8-bit limbs in a balanced Tree (depth 5 = 32 limbs).
# Carry-free recursive 4-split schoolbook: every result limb is a sum of <= 32 products
# <= 32*255*255 = 2080800 < 2^24, so no carries until one final normalize pass.
# Run: bend gen-c bend/probe/limbmul_tree.bend > lt.c && clang -O2 -DTPC_L2=3 lt.c -o lt -lm -lpthread && ./lt
def tadd(x, y):
  match x:
    case Tree/Leaf:
      match y:
        case Tree/Leaf:
          return !(x.value + y.value)
        case Tree/Node:
          return !0
    case Tree/Node:
      match y:
        case Tree/Leaf:
          return !0
        case Tree/Node:
          return ![tadd(x.left, y.left), tadd(x.right, y.right)]

def combine(ll, mid, hh):
  match ll:
    case Tree/Node:
      match mid:
        case Tree/Node:
          match hh:
            case Tree/Node:
              return ![![ll.left, tadd(ll.right, mid.left)], ![tadd(mid.right, hh.left), hh.right]]
            case Tree/Leaf:
              return !0
        case Tree/Leaf:
          return !0
    case Tree/Leaf:
      return !0

# a, b: trees of 2^d limbs -> product tree of 2^(d+1) unnormalized limbs
def tmul(a, b):
  match a:
    case Tree/Leaf:
      match b:
        case Tree/Leaf:
          return ![!(a.value * b.value), !0]
        case Tree/Node:
          return !0
    case Tree/Node:
      match b:
        case Tree/Leaf:
          return !0
        case Tree/Node:
          ll = tmul(a.left, b.left)
          lh = tmul(a.left, b.right)
          hl = tmul(a.right, b.left)
          hh = tmul(a.right, b.right)
          return combine(ll, tadd(lh, hl), hh)

def tgen(d, seed, idx):
  switch d:
    case 0:
      return !((seed * 7919 + idx * 104729) & 255)
    case _:
      return ![tgen(d-1, seed, idx * 2), tgen(d-1, seed, idx * 2 + 1)]

def flat(t, acc):
  match t:
    case Tree/Leaf:
      return List/Cons(t.value, acc)
    case Tree/Node:
      return flat(t.left, flat(t.right, acc))

# carry-propagate to 8-bit limbs and checksum in one pass
def norm(xs, carry, acc):
  match xs:
    case List/Nil:
      return acc * 31 + carry
    case List/Cons:
      s = xs.head + carry
      return norm(xs.tail, s >> 8, acc * 31 + (s & 255))

def many(d, seed):
  switch d:
    case 0:
      return norm(flat(tmul(tgen(5, seed, 0), tgen(5, seed + 1, 0)), List/Nil), 0, 0)
    case _:
      return many(d-1, seed * 2) + many(d-1, seed * 2 + 1)

def main():
  return many(16, 1)
