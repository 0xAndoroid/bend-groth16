#!/usr/bin/env bash
# Build every comparator on the GPU box (Ubuntu 24.04, CUDA 12.8 devel, RTX 5090 = sm_120).
# Layout: sources $DEV/<repo> (see comparators/box/README.md), builds/installs under $ART.
set -euxo pipefail
DEV=${DEV:-/root/dev}; ART=${ART:-/root/art}; TOOLS=${TOOLS:-/root/tools}
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
export PATH=$HOME/.cargo/bin:/usr/local/go/bin:$TOOLS:$TOOLS/node_modules/.bin:$PATH
THREADS=${THREADS:-$(nproc)}

# rapidsnark v0.0.8 (CPU)
if [ ! -x $DEV/rapidsnark/package/bin/prover ]; then
  (cd $DEV/rapidsnark && ./build_gmp.sh host && make host -j"$THREADS")
fi
# icicle-gnark v3.2.2 CUDA backend, sm_120. gnark's icicle build tag links every supported curve,
# so all four curve libraries must exist in the prefix (bn254 is the only one exercised).
for curve in bn254 bls12_377 bls12_381 bw6_761; do
  [ -f $ART/gnark-install/lib/libicicle_curve_$curve.so ] && continue
  cmake -S $DEV/icicle-gnark/icicle -B $ART/gnark-build-$curve -DCMAKE_BUILD_TYPE=Release -DCURVE=$curve -DCUDA_BACKEND=ON -DCUDA_ARCH=120 -DCMAKE_INSTALL_PREFIX=$ART/gnark-install
  cmake --build $ART/gnark-build-$curve --target install -j"$THREADS"
done
# gnark runner: CPU binary + icicle binary
cd $REPO/comparators/gpu/gnark-icicle
GOFLAGS=-mod=mod go mod tidy
go build -o $ART/gnark-cpu .
CGO_LDFLAGS="-L$ART/gnark-install/lib -licicle_device -lstdc++ -lm -Wl,-rpath,$ART/gnark-install/lib" go build -tags=icicle -o $ART/gnark-icicle .
# ICICLE-SNARK @bf00385 (vendored icicle, CUDA local backend, sm_120)
if [ ! -x $DEV/icicle-snark/target/release/icicle-snark ]; then
  cmake -S $DEV/icicle-snark/icicle -B $ART/snark-build -DCMAKE_BUILD_TYPE=Release -DCURVE=bn254 -DCUDA_BACKEND=local -DCUDA_ARCH=120 -DCMAKE_INSTALL_PREFIX=$ART/snark-install
  cmake --build $ART/snark-build --target install -j"$THREADS"
  (cd $DEV/icicle-snark && ICICLE_BACKEND_INSTALL_DIR=$ART/snark-install/lib/backend LD_LIBRARY_PATH=$ART/snark-install/lib cargo build -q --release)
fi
# open-icicle v4.0.0 bn254 frontend + local CUDA backend (isolated prefix), for the primitive bench
if [ ! -f $ART/icicle4-install/lib/libicicle_curve_bn254.so ]; then
  cmake -S $DEV/open-icicle/icicle -B $ART/icicle4-build -DCMAKE_BUILD_TYPE=Release -DCURVE=bn254 -DCUDA_BACKEND=local -DCUDA_ARCH=120 -DG2=OFF -DECNTT=OFF -DFRI=OFF -DPOSEIDON=OFF -DPOSEIDON2=OFF -DSUMCHECK=OFF -DCMAKE_INSTALL_PREFIX=$ART/icicle4-install
  cmake --build $ART/icicle4-build --target install -j"$THREADS"
fi
ln -sfn $DEV/open-icicle $REPO/comparators/gpu/icicle-prim/open-icicle
(cd $REPO/comparators/gpu/icicle-prim && ICICLE_FRONTEND_INSTALL_DIR=$ART/icicle4-install/lib cargo build -q --release)
# sppark v0.1.15 PoCs (bn254): msm bench + the ntt timer example
(cd $DEV/sppark/poc/msm-cuda && cargo bench --features bn254 --bench msm --no-run -q)
cp $REPO/comparators/gpu/sppark/ntt_timer.rs $DEV/sppark/poc/ntt-cuda/examples/ntt_timer.rs 2>/dev/null || { mkdir -p $DEV/sppark/poc/ntt-cuda/examples && cp $REPO/comparators/gpu/sppark/ntt_timer.rs $DEV/sppark/poc/ntt-cuda/examples/; }
(cd $DEV/sppark/poc/ntt-cuda && cargo build -q --release --features bn254 --example ntt_timer)
touch $ART/done-build
