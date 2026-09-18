# Sanity checks not covered by the arkworks vectors: hex printing and bit windows.
import Base
import ../src/fr.bend as F
import ../src/g1.bend as G
import ../src/fq.bend as Q

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("one  " ++ F.Fr.show(F.Fr.one()))
    IO.print("p    " ++ F.Fr.show_raw(F.Fr.modulus()))
    IO.print("w20  " ++ U32.show(F.Fr.bits_window(F.Fr.modulus(), 20n, 12n)))
    IO.print("w250 " ++ U32.show(F.Fr.bits_window(F.Fr.modulus(), 250n, 6n)))
    IO.print("w0   " ++ U32.show(F.Fr.bits_window(F.Fr.modulus(), 0n, 16n)))
    IO.print("w29  " ++ U32.show(F.Fr.bits_window(F.Fr.modulus(), 29n, 7n)))
    IO.print("gen  " ++ G.G1.show_affine(G.G1.to_affine(G.G1.double(G.G1.from_affine(G.G1Aff{Q.Fq.one(), Q.Fq.add(Q.Fq.one(), Q.Fq.one())})))))
