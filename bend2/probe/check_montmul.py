"""Reference check for montmul.bend: regenerate the same pseudo-random pairs,
compute a*b*R^-1 mod p with Python bigints, compare with the binary's output.
Usage: uv run python check_montmul.py ./montmul [count]"""
import subprocess, sys, os
P = 21888242871839275222246405745257275088548364400416034343698204186575808495617
R = 1 << 256
RINV = pow(R, -1, P)
M32 = (1 << 32) - 1
def h(i):
    i &= M32
    return (((i * 2654435761) & M32) ^ (i >> 15)) * 2246822519 & M32
def rnd(seed):
    limbs = [h((seed + j * 40503 + 1) & M32) & (0x2FFF if j == 15 else 0xFFFF) for j in range(16)]
    return sum(l << (16 * j) for j, l in enumerate(limbs))
binary = sys.argv[1]
count = int(sys.argv[2]) if len(sys.argv) > 2 else 128
env = dict(os.environ, MODE="check", CHECK=str(count))
outp = subprocess.run([binary], env=env, capture_output=True, text=True, check=True).stdout
lines = [l for l in outp.splitlines() if l.strip()]
assert len(lines) == count, (len(lines), count)
bad = 0
for line in lines:
    i, limbs = line.split(" ")
    i = int(i)
    got = sum(int(l) << (16 * j) for j, l in enumerate(limbs.split(",")))
    a, b = rnd(2 * i), rnd(2 * i + 1)
    assert a < P and b < P
    want = a * b * RINV % P
    if got != want:
        bad += 1
        if bad <= 5:
            print("MISMATCH i=%d\n  got  %x\n  want %x" % (i, got, want))
print("%d/%d montgomery products match the bigint reference" % (count - bad, count))
sys.exit(1 if bad else 0)
