#!/usr/bin/env python3
"""Bend prover stdout (3 lines: `A x y` / `B x0 x1 y0 y1` / `C x y`, canonical 0x hex) -> arkworks proof.json.

Usage:
    uv run python bend2/tools/proof_to_json.py [bend_stdout.txt] [-o proof.json] [--compare data/<K>/proof_ref.json]
Reads stdin when no input file is given; writes JSON to stdout unless -o is given.
"""
import json
import sys


def hexs(h):
    return "0x%x" % int(h, 16)


def parse(text):
    pts = {}
    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue
        tag, coords = parts[0], [hexs(c) for c in parts[1:]]
        if tag == "A" and len(coords) == 2:
            pts["a"] = {"x": coords[0], "y": coords[1]}
        elif tag == "B" and len(coords) == 4:
            pts["b"] = {"x": coords[0:2], "y": coords[2:4]}
        elif tag == "C" and len(coords) == 2:
            pts["c"] = {"x": coords[0], "y": coords[1]}
        else:
            sys.exit(f"bad proof line: {line!r}")
    missing = {"a", "b", "c"} - set(pts)
    if missing:
        sys.exit(f"missing proof components: {sorted(missing)}")
    return {"a": pts["a"], "b": pts["b"], "c": pts["c"]}


def norm(pt):
    """Arkworks point -> tuple of ints (handles {"inf":true})."""
    if pt.get("inf"):
        return ("inf",)
    flat = lambda v: tuple(int(h, 16) for h in v) if isinstance(v, list) else int(v, 16)
    return (flat(pt["x"]), flat(pt["y"]))


def main(argv):
    src, out, cmp = None, None, None
    it = iter(argv[1:])
    for a in it:
        if a == "-o":
            out = next(it)
        elif a == "--compare":
            cmp = next(it)
        else:
            src = a
    text = open(src).read() if src else sys.stdin.read()
    proof = parse(text)
    js = json.dumps(proof, indent=2) + "\n"
    if out:
        open(out, "w").write(js)
    else:
        sys.stdout.write(js)
    if cmp:
        ref = json.load(open(cmp))
        ok = True
        for k in ("a", "b", "c"):
            eq = norm(proof[k]) == norm(ref[k])
            ok &= eq
            print(f"{k.upper()}: {'EQUAL' if eq else 'DIFFERENT'}", file=sys.stderr)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv)
