# Bend 1 IO probe: read a binary file of little-endian 3-byte u24 limbs (IO/FS/read_file),
# decode to a List(u24), return (count, checksum). Then read one line from stdin (IO/input).
# Data: perl -e 'srand(1); for(1..N){ print substr(pack("V", int(rand(16777216))),0,3) }' > probe_limbs.bin
# Run (from the dir holding probe_limbs.bin): echo hello | bend run-c io.bend
def limbs(bs):
  match bs:
    case List/Nil:
      return List/Nil
    case List/Cons:
      match t = bs.tail:
        case List/Nil:
          return List/Nil
        case List/Cons:
          match t2 = t.tail:
            case List/Nil:
              return List/Nil
            case List/Cons:
              return List/Cons(bs.head | (t.head << 8) | (t2.head << 16), limbs(t2.tail))

def chk(xs, n, acc):
  match xs:
    case List/Nil:
      return (n, acc)
    case List/Cons:
      return chk(xs.tail, n + 1, acc * 31 + xs.head)

def main():
  with IO:
    r <- IO/FS/read_file("probe_limbs.bin")
    match r:
      case Result/Ok:
        line <- IO/input()
        match line:
          case Result/Ok:
            * <- IO/print(line.val)
            return wrap(chk(limbs(r.val), 0, 0))
          case Result/Err:
            return wrap(1111111)
      case Result/Err:
        return wrap(r.val)
