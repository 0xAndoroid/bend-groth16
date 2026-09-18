# Bend 1 (HVM2) parallelism probe: tree sum vs sequential loop, 2^22 leaves.
# Run: bend run-c bend/probe/parallel.bend -s   (tree)
# Sequential variant: swap main body for ssum(4194304, 0, 0)
def leaf(x):
  return (x * 2654435) ^ (x >> 7)

def tsum(d, base):
  switch d:
    case 0:
      return leaf(base)
    case _:
      return tsum(d-1, base) + tsum(d-1, base + (1 << (d-1)))

def ssum(n, i, acc):
  switch n:
    case 0:
      return acc
    case _:
      return ssum(n-1, i + 1, acc + leaf(i))

def main():
  return tsum(22, 0)
