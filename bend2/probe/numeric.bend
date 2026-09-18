# Numeric probe: every native number type and its overflow/shift/div edges.
# NB: Nat literals >= ~60000n crash the checker (unary expansion); build big Nats with Nat.pow.
# Build: bend numeric.bend -o numeric && ./numeric
import Base

def show(label: String, v: U32) -> IO(Unit):
  IO.print(label ++ " = " ++ U32.show(v))

def shown(label: String, v: Nat) -> IO(Unit):
  IO.print(label ++ " = " ++ Nat.show(v))

def main() -> IO(Unit):
  do IO<Unit>:
    show("U32 4294967295+1", (4294967295 + 1 : U32))
    show("U32 0-1", (0 - 1 : U32))
    show("U32 65535*65535", (65535 * 65535 : U32))
    show("U32 65536*65536", (65536 * 65536 : U32))
    show("U32 65536*65537", (65536 * 65537 : U32))
    show("U32 4294967295*4294967295", (4294967295 * 4294967295 : U32))
    show("U32 1<<31", (1 << 31n : U32))
    show("U32 1<<32", (1 << 32n : U32))
    show("U32 1<<33", (1 << 33n : U32))
    show("U32 (1<<31)<<1", ((1 << 31n) << 1n : U32))
    show("U32 4294967295>>16", (4294967295 >> 16n : U32))
    show("U32 4294967295>>32", (4294967295 >> 32n : U32))
    show("U32 7/2", (7 / 2 : U32))
    show("U32 7%2", (7 % 2 : U32))
    show("U32 7/0", (7 / 0 : U32))
    show("U32 7%0", (7 % 0 : U32))
    show("U32 0xF0 .&. 0x3C", (240 .&. 60 : U32))
    show("U32 0xF0 .|. 0x3C", (240 .|. 60 : U32))
    show("U32 0xF0 .^. 0x3C", (240 .^. 60 : U32))
    show("U32 not 0", U32.not(0))
    show("U32 from_nat 2^32+5", U32.from_nat(Nat.add(Nat.pow(2n, 32n), 5n)))
    show("U32 from_nat 2^40", U32.from_nat(Nat.pow(2n, 40n)))
    shown("Nat 2^32*2^15", Nat.mul(Nat.pow(2n, 32n), Nat.pow(2n, 15n)))
    shown("Nat 2^48-1", Nat.add(Nat.pow(2n, 47n), Nat.sub(Nat.pow(2n, 47n), 1n)))
    shown("Nat (2^24-1)^2 + 2*(2^24-1)", Nat.add(Nat.mul(Nat.sub(Nat.pow(2n, 24n), 1n), Nat.sub(Nat.pow(2n, 24n), 1n)), Nat.sub(Nat.pow(2n, 25n), 2n)))
    shown("Nat 5-7 (saturating?)", Nat.sub(5n, 7n))
    shown("Nat 2^47 divmod 2^24 -> div", Nat.div(Nat.pow(2n, 47n), Nat.pow(2n, 24n)))
    shown("Nat 2^47 divmod 2^24 -> mod", Nat.mod(Nat.pow(2n, 47n), Nat.pow(2n, 24n)))
    shown("Nat 12345 to_nat/from U32", U32.to_nat(12345))
    IO.print("F32 1.5*2.0 = " ++ F32.show((1.5 * 2.0 : F32)))
    IO.print("F32 16777216.0+1.0 = " ++ F32.show((16777216.0 + 1.0 : F32)))
    IO.print("F32 1.0/3.0 = " ++ F32.show((1.0 / 3.0 : F32)))
    IO.print("F32 to_u32 3000000000.0 = " ++ U32.show(F32.to_u32(3000000000.0)))
