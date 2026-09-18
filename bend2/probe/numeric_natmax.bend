# Does Nat abort past 2^48-1? (expected: runtime abort, per guide)
import Base

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("2^47 = " ++ Nat.show(Nat.pow(2n, 47n)))
    IO.print("2^47*2 = " ++ Nat.show(Nat.mul(Nat.pow(2n, 47n), 2n)))
