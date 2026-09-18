#!/bin/bash
# Bend 2 CUDA smoke + benchmarks on the RTX 5090 box (root; repo at /root/bend-groth16 on bend-groth16-integration).
# Results: bend2/bench/box_results.md. Run:  nohup /root/bend-groth16/comparators/box/bend-cuda.sh > /root/bend-cuda.log 2>&1 &
# The box has no GitHub credentials: push the branch from the mini with
#   git remote add box ssh://root@204.111.84.239:50189/root/bend-groth16   (box: git config receive.denyCurrentBranch updateInstead)
#   GIT_SSH_COMMAND='ssh -i ~/.ssh/vast_jolt' git push box origin/bend-groth16-integration:refs/heads/bend-groth16-integration
export PATH=/root/.bend/bin:/root/.bun/bin:/usr/local/cuda/bin:/home/pika/.cargo/bin:$PATH
export CARGO_HOME=/home/pika/.cargo RUSTUP_HOME=/home/pika/.rustup BEND_NO_TELEMETRY=1
PY=/usr/bin/python3            # no uv on the box; the exporters are stdlib-only
W=/root/w3; R=$W/results.txt; mkdir -p $W; : > $R
set -e
cd /root/bend-groth16
log() { echo "$*" | tee -a $R; }
dt() { awk "BEGIN{printf \"%.2f\", $2-$1}"; }

# 1. data: K=4,10,14,18,20 (K=20: gen 30 s / 3 GB RSS, export 17 s / 4 GB RSS) + vectors
cargo build --release --manifest-path ref/Cargo.toml
mkdir -p data
for K in 4 10 14 18 20; do
  [ -f data/$K/bend/witness.bin ] && continue
  /usr/bin/time -f "gen K=$K wall=%es maxrss=%MKB" ref/target/release/groth16-ref gen --log2 $K --out data/$K
  /usr/bin/time -f "export K=$K wall=%es maxrss=%MKB" $PY bend2/tools/export_bin.py data/$K
done
[ -f data/vectors/bend/fr_ops.bin ] || { ref/target/release/groth16-ref vectors --out data/vectors; $PY bend2/tools/export_bin.py --vectors data/vectors; }
$PY bend2/tools/verify_bin.py data/4 data/10 --vectors data/vectors

log "## env"
log "$(bend --version) | $(clang-19 --version | head -1) | $(nvcc --version | tail -1) | git $(git rev-parse --short HEAD)"
log "$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader)"

# 2. tests (CPU)
log "## tests"
bend2/tests/run.sh 2>&1 | tee -a $R

# 3. build: bend -o = C build + NVRTC --gpu-build (writes <bin>.gpu, cached by source hash)
log "## build"
cd bend2/bench
for b in field_mul g1_add; do
  rm -f $W/$b $W/$b.gpu
  s=$(date +%s.%N); bend $b.bend -o $W/$b; e=$(date +%s.%N); log "build $b total=$(dt $s $e)s"
  rm -f $W/$b.gpu
  s=$(date +%s.%N); $W/$b --gpu-build; e=$(date +%s.%N); log "gpu-build-only $b nvrtc=$(dt $s $e)s size=$(stat -c %s $W/$b.gpu)"
done
cd $W

# run BIN MODE N FD [args...] — 3 runs; the binary prints its own ms + checksum (xor / sum)
run() {
  local bin=$1 mode=$2 n=$3 fd=$4; shift 4
  for i in 1 2 3; do
    s=$(date +%s.%N); out=$(MODE=$mode N=$n FD=$fd ./$bin "$@" 2>&1); e=$(date +%s.%N)
    log "$out args=[$*] wall=$(dt $s $e)s"
  done
}

nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu --format=csv,noheader -l 1 > $W/smi.log 2>&1 &
SMI=$!

log "## field_mul"
for n in 20 24; do
  for t in 1 24 48; do run field_mul cpu $n 14 --threads $t; done
  for fd in 14 16 18 20; do run field_mul gpu $n $fd; done
done
for n in 26 28; do run field_mul cpu $n 16 --threads 48; for fd in 18 20; do run field_mul gpu $n $fd; done; done
run field_mul gpu 30 20
run field_mul gpu 28 20 --gpu 8GB
run field_mul gpu 28 20 --gpu off --threads 48

log "## g1_add (sum depends on FD: compare CPU and GPU at the same FD)"
for t in 1 24 48; do run g1_add cpu 20 14 --threads $t; done
for fd in 14 16 18; do run g1_add cpu 20 $fd --threads 48; run g1_add gpu 20 $fd; done
for n in 22 24; do for fd in 16 18 20; do run g1_add cpu $n $fd --threads 48; run g1_add gpu $n $fd; done; done
run g1_add gpu 26 20
run g1_add gpu 26 20 --gpu off --threads 48
run g1_add gpu 24 20 --gpu 8GB

kill $SMI 2>/dev/null; wait $SMI 2>/dev/null || true
log "## nvidia-smi peak memory.used: $(awk -F', ' '{gsub(/ MiB/,"",$2); if($2+0>m)m=$2+0} END{print m" MiB"}' $W/smi.log)"
touch /root/done-bend-cuda
