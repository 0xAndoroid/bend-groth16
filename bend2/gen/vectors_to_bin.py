"""Minimal fallback converter: data/vectors/{fr,fq,g1,g2}_ops.json -> data/vectors/bend/*.bin
(bend2/FORMAT.md layout). The canonical converter is bend2/tools/export_bin.py; this one
exists so the field/curve lane is not blocked on it. stdlib only.
Run: uv run python bend2/gen/vectors_to_bin.py [data/vectors]"""
import json
import struct
import sys
from pathlib import Path

R = 1 << 256


def limbs(x):
    return b"".join(struct.pack("<I", (x >> (16 * j)) & 0xFFFF) for j in range(16))


def fe(hx, p, mont=True):
    x = int(hx, 16)
    return limbs((x * R) % p if mont else x)


def pt(j, p, deg):
    if j.get("inf"):
        return limbs(0) * (2 * deg)
    xs = j["x"] if deg == 2 else [j["x"]]
    ys = j["y"] if deg == 2 else [j["y"]]
    return b"".join(fe(c, p) for c in xs + ys)


def main(vec):
    out = vec / "bend"
    out.mkdir(exist_ok=True)
    fr = json.load(open(vec / "fr_ops.json"))
    fq = json.load(open(vec / "fq_ops.json"))
    r = int(fr["constants"]["p"], 16)
    q = int(fq["constants"]["p"], 16)
    for name, d, p in (("fr_ops", fr, r), ("fq_ops", fq, q)):
        cases = d["cases"]
        buf = [struct.pack("<I", len(cases))]
        for c in cases:
            buf += [fe(c[k], p) for k in ("a", "b", "add", "sub", "mul", "neg_a", "inv_a", "sq_a")]
            buf.append(fe(c["a"], p, mont=False))
        (out / f"{name}.bin").write_bytes(b"".join(buf))
    for name, deg in (("g1_ops", 1), ("g2_ops", 2)):
        cases = json.load(open(vec / f"{name}.json"))
        buf = [struct.pack("<I", len(cases))]
        for c in cases:
            buf += [pt(c["p"], q, deg), pt(c["q"], q, deg), fe(c["k"], r, mont=False)]
            buf += [pt(c[k], q, deg) for k in ("add", "double_p", "neg_p", "mul_pk")]
        (out / f"{name}.bin").write_bytes(b"".join(buf))
    print("wrote", sorted(f.name for f in out.iterdir()))


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "data/vectors"))
