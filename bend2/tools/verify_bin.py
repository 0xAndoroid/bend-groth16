#!/usr/bin/env python3
"""Self-check: re-read data/<K>/bend/*.bin (or data/vectors/bend/*.bin) and compare against the JSON.

Usage:
    uv run python bend2/tools/verify_bin.py data/<K> [data/<K> ...] [--vectors data/vectors]
Every element is converted back (Montgomery -> canonical) and compared to the JSON integer;
counts must match the header; the R1CS CSR must reproduce the JSON rows. Exit 1 on any mismatch.
"""
import json
import os
import struct
import sys
import time

FR = 21888242871839275222246405745257275088548364400416034343698204186575808495617
FQ = 21888242871839275222246405745257275088696311157297823662689037894645226208583
R256 = 1 << 256
RINV_FR = pow(R256, -1, FR)
RINV_FQ = pow(R256, -1, FQ)
_U32x16 = struct.Struct("<16I")
_U16 = struct.Struct("<16H")


class Reader:
    def __init__(self, path):
        self.buf = open(path, "rb").read()
        self.pos = 0
        self.path = path

    def u32(self, n=1):
        v = struct.unpack_from("<%dI" % n, self.buf, self.pos)
        self.pos += 4 * n
        return v if n > 1 else v[0]

    def elem(self):
        words = _U32x16.unpack_from(self.buf, self.pos)
        self.pos += 64
        assert all(w < 0x10000 for w in words), f"{self.path}: limb > 16 bits"
        return int.from_bytes(_U16.pack(*words), "little")

    def fr(self):
        return self.elem() * RINV_FR % FR

    def fq(self):
        return self.elem() * RINV_FQ % FQ

    def fr_canon(self):
        return self.elem()

    def g1(self):
        x, y = self.elem(), self.elem()
        if x == 0 and y == 0:
            return ("inf",)
        return (x * RINV_FQ % FQ, y * RINV_FQ % FQ)

    def g2(self):
        c = [self.elem() for _ in range(4)]
        if not any(c):
            return ("inf",)
        c = [v * RINV_FQ % FQ for v in c]
        return ((c[0], c[1]), (c[2], c[3]))

    def done(self):
        assert self.pos == len(self.buf), f"{self.path}: {len(self.buf) - self.pos} trailing bytes"


def jpt(pt):
    if pt.get("inf"):
        return ("inf",)
    flat = lambda v: tuple(int(h, 16) for h in v) if isinstance(v, list) else int(v, 16)
    return (flat(pt["x"]), flat(pt["y"]))


def jint(h):
    return int(h, 16)


class Check:
    def __init__(self):
        self.n = 0
        self.bad = 0

    def eq(self, got, want, what):
        self.n += 1
        if got != want:
            self.bad += 1
            if self.bad <= 5:
                print(f"  MISMATCH {what}: got {got} want {want}")

    def seq(self, rd, fn, items, conv, what):
        for i, it in enumerate(items):
            self.eq(fn(rd), conv(it), f"{what}[{i}]")


def load(d, name):
    with open(os.path.join(d, name)) as f:
        return json.load(f)


def verify_circuit(d):
    t0 = time.time()
    b = os.path.join(d, "bend")
    ck = Check()
    hdr = Reader(os.path.join(b, "header.bin"))
    n, ni, nw, dlog, n_a, n_b, n_h, n_l = hdr.u32(8)
    hdr.done()
    r1cs = load(d, "r1cs.json")
    ck.eq((n, ni, nw), (r1cs["num_constraints"], r1cs["num_instance"], r1cs["num_witness"]), "header n/ni/nw")
    for m in "abc":
        rd = Reader(os.path.join(b, f"r1cs_{m}.bin"))
        nnz = rd.u32()
        offs = rd.u32(n + 1)
        ck.eq(nnz, sum(len(r) for r in r1cs[m]), f"r1cs_{m} nnz")
        ck.eq((offs[0], offs[-1]), (0, nnz), f"r1cs_{m} offsets ends")
        entries = [(rd.u32(), rd.fr()) for _ in range(nnz)]
        rd.done()
        for i, row in enumerate(r1cs[m]):
            ck.eq(entries[offs[i]:offs[i + 1]], [(c, jint(v)) for c, v in row], f"r1cs_{m} row {i}")
    del r1cs
    z = load(d, "witness.json")["z"]
    rd = Reader(os.path.join(b, "witness.bin"))
    ck.eq(len(rd.buf), 64 * (ni + nw), "witness.bin size")
    ck.seq(rd, Reader.fr, z, jint, "witness")
    rd.done()
    del z
    rs = load(d, "proof_ref_rs.json")
    rd = Reader(os.path.join(b, "rs.bin"))
    ck.seq(rd, Reader.fr, [rs["r"], rs["s"]], jint, "rs")
    rd.done()
    pr = load(d, "proof_ref.json")
    rd = Reader(os.path.join(b, "proof_ref.bin"))
    ck.eq(rd.g1(), jpt(pr["a"]), "proof A")
    ck.eq(rd.g2(), jpt(pr["b"]), "proof B")
    ck.eq(rd.g1(), jpt(pr["c"]), "proof C")
    rd.done()
    pk = load(d, "pk.json")
    ck.eq(1 << dlog, pk["domain_size"], "domain_log2")
    ck.eq((n_a, n_b, n_h, n_l), (len(pk["a_query"]), len(pk["b_g1_query"]), len(pk["h_query"]), len(pk["l_query"])), "header query lengths")
    ck.eq(n_b, len(pk["b_g2_query"]), "n_b vs b_g2_query")
    rd = Reader(os.path.join(b, "pk_g1.bin"))
    ck.seq(rd, Reader.g1, [pk["alpha_g1"], pk["beta_g1"], pk["delta_g1"]], jpt, "pk_g1")
    rd.done()
    rd = Reader(os.path.join(b, "pk_g2.bin"))
    ck.seq(rd, Reader.g2, [pk["beta_g2"], pk["delta_g2"]], jpt, "pk_g2")
    rd.done()
    pts = 0
    for fname, key, fn, sz in (("pk_a.bin", "a_query", Reader.g1, 128), ("pk_b1.bin", "b_g1_query", Reader.g1, 128),
                               ("pk_b2.bin", "b_g2_query", Reader.g2, 256), ("pk_h.bin", "h_query", Reader.g1, 128),
                               ("pk_l.bin", "l_query", Reader.g1, 128)):
        rd = Reader(os.path.join(b, fname))
        ck.eq(len(rd.buf), sz * len(pk[key]), f"{fname} size")
        ck.seq(rd, fn, pk[key], jpt, key)
        rd.done()
        pts += len(pk[key])
    print(f"{d}: {ck.n} checks, {ck.bad} mismatches ({pts} pk points, {ni + nw} witness, 3x{n} r1cs rows) in {time.time() - t0:.1f}s")
    return ck.bad


def verify_vectors(d):
    t0 = time.time()
    b = os.path.join(d, "bend")
    ck = Check()
    for name, fr_or_fq, p in (("fr_ops", Reader.fr, FR), ("fq_ops", Reader.fq, FQ)):
        cases = load(d, name + ".json")["cases"]
        rd = Reader(os.path.join(b, name + ".bin"))
        ck.eq(rd.u32(), len(cases), f"{name} count")
        for i, c in enumerate(cases):
            for k in ("a", "b", "add", "sub", "mul", "neg_a", "inv_a", "sq_a"):
                ck.eq(fr_or_fq(rd), jint(c[k]), f"{name}[{i}].{k}")
            ck.eq(rd.fr_canon(), jint(c["a"]), f"{name}[{i}].a_canonical")
            # cross-check our Montgomery constant against arkworks' a_mont
            ck.eq(jint(c["a"]) * R256 % p, jint(c["a_mont"]), f"{name}[{i}].a_mont")
        rd.done()
    for name, fn in (("g1_ops", Reader.g1), ("g2_ops", Reader.g2)):
        cases = load(d, name + ".json")
        rd = Reader(os.path.join(b, name + ".bin"))
        ck.eq(rd.u32(), len(cases), f"{name} count")
        for i, c in enumerate(cases):
            ck.eq(fn(rd), jpt(c["p"]), f"{name}[{i}].p")
            ck.eq(fn(rd), jpt(c["q"]), f"{name}[{i}].q")
            ck.eq(rd.fr_canon(), jint(c["k"]), f"{name}[{i}].k")
            for k in ("add", "double_p", "neg_p", "mul_pk"):
                ck.eq(fn(rd), jpt(c[k]), f"{name}[{i}].{k}")
        rd.done()
    for c in load(d, "msm_small.json"):
        n = c["size"]
        rd = Reader(os.path.join(b, f"msm_small_{n}.bin"))
        ck.eq(rd.u32(), n, f"msm_{n} n")
        ck.seq(rd, Reader.g1, c["points"], jpt, f"msm_{n}.points")
        ck.seq(rd, Reader.fr_canon, c["scalars"], jint, f"msm_{n}.scalars")
        ck.eq(rd.g1(), jpt(c["result"]), f"msm_{n}.result")
        rd.done()
    for c in load(d, "ntt_small.json"):
        n = c["size"]
        rd = Reader(os.path.join(b, f"ntt_small_{n}.bin"))
        ck.eq(rd.u32(), n, f"ntt_{n} n")
        ck.eq(rd.fr(), jint(c["omega"]), f"ntt_{n}.omega")
        ck.eq(rd.fr(), jint(c["domain_size_inv"]), f"ntt_{n}.n_inv")
        for k in ("coeffs", "evals", "icoeffs_of_evals"):
            ck.seq(rd, Reader.fr, c[k], jint, f"ntt_{n}.{k}")
        rd.done()
    print(f"{d}: {ck.n} checks, {ck.bad} mismatches in {time.time() - t0:.2f}s")
    return ck.bad


def main(argv):
    bad = 0
    it = iter(argv[1:])
    for a in it:
        bad += verify_vectors(next(it)) if a == "--vectors" else verify_circuit(a)
    print("ALL OK" if bad == 0 else f"FAILED: {bad} mismatches")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv)
