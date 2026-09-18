# Bend 1 (bend-lang 0.2.38 / HVM2) numeric probe: u24 wrap, bit ops, i24, f24.
# Run: bend run-c bend/probe/numeric.bend
def main():
  a = 16777215 + 1
  b = 4095 * 4095
  c = 4096 * 4096
  d = 16777215 * 16777215
  e = 0 - 1
  f = 61680 & 65280
  g = 61680 | 15
  h = 61680 ^ 65535
  i = 1 << 23
  j = 1 << 24
  k = 16777215 >> 12
  l = 16777215 / 4096
  m = 16777215 % 4096
  n = 7 / 0
  o = +12 * -3
  p = 1.5 * 2.0
  q = 4095 * 4095 + 4095 + 4095
  r = +8388607 + +1
  s = -8388608 - +1
  t = 16777215 == -1
  u = 1.0 / 3.0
  return [a, b, c, d, e, f, g, h, i, j, k, l, m, n, q, o, r, s, t, p, u]
