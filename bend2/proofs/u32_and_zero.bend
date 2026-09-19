# U32 primitives are not opaque: Base defines U32 as `U32{data: Word(32n)}` and
# U32.and/add/mul/... as recursion over that 32-bit bit vector (base.bend
# `Word.*`). So properties of the machine ops are provable by induction on the
# word. Here: x & 0 == 0 for every U32 x, via a Word lemma for every width n.
import Base

law Word.and_zero:
  for n: Nat
  for w: Word(n)
  {Word.and(n, w, Word.zero(n)) == Word.zero(n) : Word(n)}

def Word.and_zero(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case True{}:
              %Word.and_zero(p, t) : {WCon{False{}, Word.and(p, t, Word.zero(p))} == WCon{False{}, _} : Word(1n+p)}
              {==}
            case False{}:
              %Word.and_zero(p, t) : {WCon{False{}, Word.and(p, t, Word.zero(p))} == WCon{False{}, _} : Word(1n+p)}
              {==}

law U32.and_zero:
  for x: U32
  {U32.and(x, 0) == 0 : U32}

def U32.and_zero(x):
  match x:
    case U32{w}:
      Equal.cong(Word(32n), U32, v => U32{v}, Word.and(32n, w, Word.zero(32n)), Word.zero(32n), Word.and_zero(32n, w))
