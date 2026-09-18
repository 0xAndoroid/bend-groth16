#!/usr/bin/env python3
"""Export arkworks JSON (data/<K>/*.json, data/vectors/*.json) to the frozen Bend binary format.

See bend2/FORMAT.md. Usage:
    uv run python bend2/tools/export_bin.py data/<K>            -> data/<K>/bend/*.bin
    uv run python bend2/tools/export_bin.py --vectors data/vectors -> data/vectors/bend/*.bin
Stdlib only.
"""
import json
import os
import struct
import sys
import time

FR = 21888242871839275222246405745257275088548364400416034343698204186575808495617
FQ = 21888242871839275222246405745257275088696311157297823662689037894645226208583
R256 = 1 << 256
ZERO_G1 = bytes(128)
ZERO_G2 = bytes(256)
_U16 = struct.Struct("<16H")
_U32x16 = struct.Struct("<16I")


def limbs(v):
    """Canonical integer (< 2^256) -> 16 u32 words, each one 16-bit limb, little-endian."""
    return _U32x16.pack(*_U16.unpack(v.to_bytes(32, "little")))


def fr_mont(h):
    return limbs(int(h, 16) * R256 % FR)


def fq_mont(h):
    return limbs(int(h, 16) * R256 % FQ)


def fr_canon(h):
    return limbs(int(h, 16))


def g1(pt):
    if pt.get("inf"):
        return ZERO_G1
    return fq_mont(pt["x"]) + fq_mont(pt["y"])


def g2(pt):
    if pt.get("inf"):
        return ZERO_G2
    x, y = pt["x"], pt["y"]
    return fq_mont(x[0]) + fq_mont(x[1]) + fq_mont(y[0]) + fq_mont(y[1])


def u32(*vals):
    return struct.pack("<%dI" % len(vals), *vals)


def write(path, chunks):
    with open(path, "wb") as f:
        f.write(b"".join(chunks))
    return os.path.getsize(path)


def load(d, name):
    with open(os.path.join(d, name)) as f:
        return json.load(f)


def csr(rows):
    """[[ [col, coeff], ... ] per row] -> u32 nnz; u32 offsets[n+1]; (u32 col, Fr coeff)*nnz."""
    offsets = [0]
    entries = []
    for row in rows:
        for col, coeff in row:
            entries.append(u32(col) + fr_mont(coeff))
        offsets.append(len(entries))
    return [u32(len(entries)), u32(*offsets)] + entries


def export_circuit(d):
    out = os.path.join(d, "bend")
    os.makedirs(out, exist_ok=True)
    sizes = {}

    def emit(name, chunks):
        sizes[name] = write(os.path.join(out, name), chunks)

    t0 = time.time()
    r1cs = load(d, "r1cs.json")
    n, ni, nw = r1cs["num_constraints"], r1cs["num_instance"], r1cs["num_witness"]
    emit("r1cs_a.bin", csr(r1cs["a"]))
    emit("r1cs_b.bin", csr(r1cs["b"]))
    emit("r1cs_c.bin", csr(r1cs["c"]))
    del r1cs

    z = load(d, "witness.json")["z"]
    assert len(z) == ni + nw, (len(z), ni, nw)
    public = load(d, "public.json")["inputs"]
    assert [int(h, 16) for h in z[1:ni]] == [int(h, 16) for h in public]
    emit("witness.bin", [fr_mont(h) for h in z])
    del z

    rs = load(d, "proof_ref_rs.json")
    emit("rs.bin", [fr_mont(rs["r"]), fr_mont(rs["s"])])
    pr = load(d, "proof_ref.json")
    emit("proof_ref.bin", [g1(pr["a"]), g2(pr["b"]), g1(pr["c"])])

    t1 = time.time()
    pk = load(d, "pk.json")
    t2 = time.time()
    dom = pk["domain_size"]
    assert dom & (dom - 1) == 0
    n_a, n_b, n_h, n_l = len(pk["a_query"]), len(pk["b_g1_query"]), len(pk["h_query"]), len(pk["l_query"])
    assert len(pk["b_g2_query"]) == n_b
    emit("header.bin", [u32(n, ni, nw, dom.bit_length() - 1, n_a, n_b, n_h, n_l)])
    emit("pk_g1.bin", [g1(pk["alpha_g1"]), g1(pk["beta_g1"]), g1(pk["delta_g1"])])
    emit("pk_g2.bin", [g2(pk["beta_g2"]), g2(pk["delta_g2"])])
    emit("pk_a.bin", [g1(p) for p in pk["a_query"]])
    emit("pk_b1.bin", [g1(p) for p in pk["b_g1_query"]])
    emit("pk_b2.bin", [g2(p) for p in pk["b_g2_query"]])
    emit("pk_h.bin", [g1(p) for p in pk["h_query"]])
    emit("pk_l.bin", [g1(p) for p in pk["l_query"]])
    t3 = time.time()
    total = sum(sizes.values())
    for k in sorted(sizes):
        print(f"  {k:16s} {sizes[k]:>12,d} B")
    print(f"{d}: n={n} ni={ni} nw={nw} domain=2^{dom.bit_length() - 1} n_a={n_a} n_b={n_b} n_h={n_h} n_l={n_l}")
    print(f"  total {total / 1e6:.1f} MB; r1cs+witness {t1 - t0:.1f}s, pk.json load {t2 - t1:.1f}s, pk export {t3 - t2:.1f}s, wall {t3 - t0:.1f}s")


def export_vectors(d):
    out = os.path.join(d, "bend")
    os.makedirs(out, exist_ok=True)
    sizes = {}

    def emit(name, chunks):
        sizes[name] = write(os.path.join(out, name), chunks)

    t0 = time.time()
    for name, mont in (("fr_ops", fr_mont), ("fq_ops", fq_mont)):
        cases = load(d, name + ".json")["cases"]
        chunks = [u32(len(cases))]
        for c in cases:
            chunks += [mont(c[k]) for k in ("a", "b", "add", "sub", "mul", "neg_a", "inv_a", "sq_a")]
            chunks.append(fr_canon(c["a"]))
        emit(name + ".bin", chunks)
    for name, pt in (("g1_ops", g1), ("g2_ops", g2)):
        cases = load(d, name + ".json")
        chunks = [u32(len(cases))]
        for c in cases:
            chunks += [pt(c["p"]), pt(c["q"]), fr_canon(c["k"]), pt(c["add"]), pt(c["double_p"]), pt(c["neg_p"]), pt(c["mul_pk"])]
        emit(name + ".bin", chunks)
    for c in load(d, "msm_small.json"):
        n = c["size"]
        assert len(c["points"]) == len(c["scalars"]) == n
        emit(f"msm_small_{n}.bin", [u32(n)] + [g1(p) for p in c["points"]] + [fr_canon(k) for k in c["scalars"]] + [g1(c["result"])])
    for c in load(d, "ntt_small.json"):
        n = c["size"]
        assert len(c["coeffs"]) == len(c["evals"]) == len(c["icoeffs_of_evals"]) == n
        chunks = [u32(n), fr_mont(c["omega"]), fr_mont(c["domain_size_inv"])]
        for k in ("coeffs", "evals", "icoeffs_of_evals"):
            chunks += [fr_mont(h) for h in c[k]]
        emit(f"ntt_small_{n}.bin", chunks)
    for k in sorted(sizes):
        print(f"  {k:16s} {sizes[k]:>12,d} B")
    print(f"{d}: vectors total {sum(sizes.values()) / 1e6:.2f} MB, wall {time.time() - t0:.2f}s")


def main(argv):
    if len(argv) == 3 and argv[1] == "--vectors":
        export_vectors(argv[2])
    elif len(argv) == 2:
        export_circuit(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
