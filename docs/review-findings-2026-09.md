# Review findings (September 2026)

Independent read-only review of the repository at `c72aa5d` against the installed Bend 2.0.5 runtime/guide, the ark-groth16 0.5 source and the benchmark JSON. Line numbers refer to that revision. The P1/P2 items in the first table were fixed in `7b5c495` / `fb129e7` (bench loader sized from `header.bin`, `bench_prover.sh` enforcing the CFG mode and rejecting unverified runs, `run.sh` running every test); the remaining tables are kept as the caveat list for reading the numbers.

## Fixed before publication

| Priority | Location | Finding |
|---|---|---|
| P1 | `bend2/bench/msm.bend:73`, `:84`, `:144` | Benchmark input still wraps. G1 allocates 2^18 records, but `pk_a.bin` has 262146: 33554688 bytes versus 33554432 capacity. Witness has 16777344 bytes versus 16777216 capacity. Last two records overwrite the first two. G2 allocates only the requested n records but reads the entire 262146-record file; smaller cases retain its tail. `B.scalars` then cycles modulo 262146 through an array holding only 262144 records. Cross-backend equality validates identical altered inputs, not the claimed first n key/witness records. Full prover allocations at `src/groth16.bend:243` are correctly header-sized and unaffected. |
| P1 | `bend2/scripts/bench_prover.sh:17`, `:22`, `:46` | `cfg` is only a JSON label: `run gpu ...` never sets `BENDG_GPU=1`; `run cpu1 ...` never selects one thread; inherited GPU env can also mislabel CPU rows. Errors are swallowed and missing totals become 0-ms samples. Existing saved rows have true verification flags, but the advertised runner can publish CPU timings as GPU or fold failed executions into medians. Enforce/record selected execution mode and reject failed/incomplete samples. |
| P2 | `comparators/gpu/icicle_snark_bench.py:49`, `:53`; `ref/src/bench.rs:89`, `:95` | ICICLE-SNARK overwrites the same proof through cold + all warm runs and verifies only the final result. Arkworks discards every timed full/matrices proof; only one earlier untimed full proof is checked. Thus “every proof verified” is false for these paths (`docs/box.md:57`, `docs/comparators.md:226`). Verify each result outside its timer, or explicitly limit the claim and exclude unverified samples from that guarantee. Both gnark runners and both Circom CLI runners do verify every timed proof. |
| P2 | `bend2/tests/run.sh:12` | Fresh-data bootstrap invokes the obsolete four-file fallback converter, which never emits MSM/NTT vectors. The expanded runner later opens those missing files. Use the existing canonical exporter; no new converter needed. Also `run.sh:30` omits `test_prove.sh` despite “every bend2 test” at line 2. |
| P1, report | `bend2/bench/prover_results.md:116`, `:123`, `:125`; `bend2/bench/box_results.md:59` | Unsupported causal/language conclusions: timing and 1-Hz GPU utilization do not establish “~1000x under-occupied”, CPU bottleneck attribution, or saturation. A stage-parallel NTT already exists (`src/ntt.bend:152`, `:249`, `:268`); owned sorted/segmented MSM designs are possible without shared arrays, as the audit itself says at `used-properly-audit.md:82`. The old prediction that MSM/NTT become ~100x faster on CUDA is contradicted by current full-prover and primitive tables. Preserve measured times; mark explanations as hypotheses and remove impossibility/extrapolation claims. |

## Proof formulas and timer boundaries

No formula defect found for the frozen SquareChain input shape:

```text
src/groth16.bend:183   ea[N+i] = z[i], i < ni; only A gets input rows
src/ntt.bend:464       three ifft -> coset_fft pipelines
src/ntt.bend:465       zinv = (5^D - 1)^-1
src/ntt.bend:466       h = coset_ifft((A*B-C)*zinv)
src/groth16.bend:313   A  = alpha + MSM(a_query,z) + r*delta
src/groth16.bend:314   B1 = beta1 + MSM(b1_query,z) + s*delta1
src/groth16.bend:315   B2 = beta2 + MSM(b2_query,z) + s*delta2
src/groth16.bend:316   C  = s*A + r*B1 - r*s*delta1 + MSM(L,z[2..]) + MSM(H,h)
```

`z[0]=1`; the two positive `r*s*delta` contributions in `s*A+r*B1` lose exactly one copy. This agrees with installed ark-groth16 0.5 `prover.rs:92`, `:101`, `:113`, `:122` and `r1cs_to_qap.rs:176`. `z[2..]` is correct specifically because this benchmark has `ni=2`. `prove.sh:20` checks all three coordinates against the reference and `:22` verifies the resulting proof.

| Timer | Actual boundary / comparison constraint |
|---|---|
| Bend `T total`, `prove.bend:135`, `:156`, `:166` | Header + all key/matrix/witness loading, evaluation, canonical conversion, QAP, five MSMs, affine accumulation, final combination, and proof formatting/printing. Excludes witness generation, setup, Bend compilation, runtime startup, GPU context/pipeline loading, JSON conversion, external verification. It is neither warm in-memory prove-only nor whole CLI wall time. |
| Bend phases, `prove.bend:142`, `:144`; `src/groth16.bend:263`, `:285` | `evals` includes scalar conversion/copying; `qap` includes h-to-canonical conversion; each MSM includes its affine accumulator update. `total - sum(phases)` includes final combination and printing. Per-phase medians need not sum to the total median. |
| GPU initialization | Installed `~/.bend/app/2.0.5/wYTOWc/bend2/comp.ts:5898` calls `corpus_setup` before `io_loop`; `:5101` loads the GPU pipeline there. Startup is outside every Bend `T` line, unlike Circom process-wall timers and first-process GPU comparator measurements. No explicit Bend warm-up proof is discarded. |
| CPU-labelled Bend configs, `prover_results.md:9`, `:10`; raw `args` | At recorded HEAD `1628377`, the binary contains bangs. Runtime `comp.ts:5894` enables its GPU-backed arena by default even when `BENDG_GPU` is absent and arithmetic follows CPU branches. CUDA `:4913` uses device-preferred managed memory; `:5066` changes allocator policy. None of the CPU args records `--gpu off`. The bang-bearing binary also changes the `!BANGS` fast path at `:5111`. Consequently “everything else identical” between pre-switch v1 and current v2 is not established; record the actual binary revision and isolate the GPU-switch change before attributing regression to MSM defaults. Even `--gpu off` alone does not restore the no-bangs fast path. |
| Arkworks, `ref/src/bench.rs:79`, `:84`, `:89`, `:95` | Setup and chain values outside both timers. Full mode includes circuit clone/synthesis and matrix construction; matrices mode uses precomputed matrices/assignment and fixed r,s. In-memory keys, one discarded warm-up per mode. Compare Bend compute-only with matrices mode, not Bend load-inclusive total with this number without a label. |
| gnark, `comparators/gnark/main.go:127`, `:134`; GPU runner `:182` | Compiled rows/setup outside; solver included in every proof. Standalone `solve_ms` is a different execution, not an exact phase subtraction. Box uses 47 Go threads, Bend uses 48; Mac uses 10. |
| Circom CLI, `comparators/circom/bench.py:46`; box `bench_circom.py:46` | Process start + key/witness reads + proof + output writes; setup and expanded witness generation excluded. Repeated processes can use warm filesystem cache: “cold” means process-cold, not cold storage. `--threads` only writes metadata in these Python harnesses; it does not constrain execution. |
| GPU comparator transfer scope | `icicle-prim/src/main.rs:63`, `:65`, `:67`: device MSM excludes base/scalar upload. `:69`: host-scalar variant still has cached bases. sppark includes points+scalars H2D. Bend's managed-memory ownership transfers, array conversions and joins are inside phase timings; direct ratios against device-resident ICICLE are not kernel-for-kernel comparisons. |

## Circuit identity and validation scope

| Location | Result / missing evidence |
|---|---|
| `ref/src/gen.rs:77`; `comparators/gnark/main.go:45`; GPU runner `main.go:33`; `comparators/circom/square_chain.circom:14` | Source implements the same logical N squaring rows, N+2 wires including constant, one public scalar. Gnark's raw final R1C avoids an extra equality row. Circom removes two aliases under O1; box generator checks the count at `comparators/box/circom/gen.sh:13`. |
| `docs/comparators.md:66`, `:68` | The promised common x0=3 and normalized matrix hash are not implemented across all harnesses. Arkworks/Bend use seeded random x0 (`ref/src/circuit.rs:39`); Mac Circom uses 12345678901234567890 (`comparators/circom/bench.py:57`); gnark/box Circom use 3. Same logical circuit, different witnesses/public values. No cross-frontend normalized-row hash is retained. |
| `docs/comparators.md:70`; `ref/README.md:19` | Gnark QAP domain N; arkworks/Bend and Circom-family domain 2N. This is a real reduction difference, not an extra logical-constraint count. `comparators/circom/README.md:17` incorrectly calls N+1 the domain size: actual radix-2 domain is 2N. |
| `comparators/gpu/icicle-prim/src/main.rs:72`, `:97`, `:99`; `comparators/gpu/sppark/ntt_timer.rs:30` | GPU primitive checks lack the planned independent arkworks oracle. MSM compares two CUDA API paths. `ntt_device.*.roundtrip_ok` is populated from the host-buffer API result, not the timed device buffer. These programs record false check flags without failing; `primitives.py` does not reject them. Current flags are true, but do not claim an independent oracle or device-path round-trip was checked. |
| `comparators/gpu/primitives.py:37`, `:47`; `docs/box.md:70` | sppark MSM is a Criterion estimate/interval with recorded sample size 20 and 1-second warm-up, not “median of 10 after one warm-up” as the table heading says. The other primitive timers use ten direct samples. |

## Numeric / metadata mismatches

Main timing tables in `prover_results.md`, `docs/box.md`, and both CPU comparator READMEs agree with their JSON within displayed precision. All 35 full-prover rows have matching sample lists; integer presentation differences are listed below. Actual discrepancies:

| Location / quoted value | Stored value or source | Impact |
|---|---|---|
| `bend2/bench/msm_results.md:72`: gnark 0.85 s | `bench/gnark-macmini.json` `msm_g1.20.ms=399.895583` ms | Stale denominator by ~2.1x. Current v2 11087 ms / current gnark = ~27.7x, not ~13x. |
| `bench/bend2-macmini.json:14`: unversioned `msm_g1` | All six sizes are v1; `bench/bend2-box.json:16` same key is v2 | Same schema key is different algorithm across hosts. Mini has no `msm_g1_v1` or retained v2 primitive series. `prover_results.md:105` claiming mini primitive numbers copied omits the v2 section. |
| `bench/bend2-macmini.json:13`: v1 default c=8/12 | `msm_g1.14.gpu=8502` used c=10; `.16.gpu=28327` used c=12, while CPU c=8 (`msm_results.md:18`, `:19`) | Metadata labels these as defaults; raw entries omit c/fd. Those CPU/GPU ratios are not fixed-config backend scaling. |
| `bend2/bench/ntt_results.md:36`: Metal 2–6x slower | JSON `ntt.10.gpu/cpu_all=62/3=20.67`; `.12=75/7=10.71`; `.14=114/15=7.60`; `.16=392/47=8.34`; `.18=1123/158=7.11`; `.20=3381/529=6.39` | All stored FFT ratios exceed the claimed upper bound; the other transforms reach 22x. |
| `bend2/bench/msm_results.md:72`, `src/msm.bend:14`: 870 MB / 6.8 MB per leaf | `src/msm.bend:236`: 32 allocated windows, 1024 buckets, 64 U32 words: 8 MiB/leaf, 1 GiB for 128 G1 leaves; G2 twice that | 870 MB counts 26 logical windows and misses padding; excludes join/input arrays too. Audit `used-properly-audit.md:82` already corrects it. |
| `bend2/bench/prover_results.md:111`: load+evals+QAP 7% on both hosts | `bench/bend2-box.json` `prove.18.cpu_all.phases_ms`: 883.5+239.5+721=1844 ms; `/34906.5=5.28%`; mini=6.69% | Small numerical claim error; use 5% box / 7% mini. |
| `bend2/bench/prover_results.md:119`: 2.3x more hardware threads | JSON top-level `threads`: box 48, mini 10 = 4.8x (gnark box actually 47) | No defined quantity supports “threads per leaf-tree level”; remove this causal explanation. |
| `bench/box-cpu-{snarkjs,rapidsnark}.json:5`: version | `versions.snarkjs="[binary.file]"`, versus documented 0.7.6 | `comparators/box/bench_circom.py:23` parses the last help token, not version. Box `git_head="box"` also loses runner revision. |
| `docs/box.md:67`: driver wall within 0.1 ms | `bench/box-gpu-icicle-snark.json` `prove.10.first_wall_ms=146.25`, `first_prove_ms=134.66` | True for warm medians, false for first command; qualify warm. |
| `bench/README.md:50`: 3 G1 MSMs | Installed arkworks `prover.rs:101` also computes B1 whenever r!=0; Bend times `msm_b1` | Actual nonzero-r proof has four G1 MSMs plus one G2. Primitive-sum formula at line 52 is short by one G1 MSM. |

Unretained data, not numeric contradictions: `bench/bend2-*.json` retain only aggregate primitive times, no original samples/checksums; mini v2 MSM, G2 MSM, inverse/coset/QAP NTT, and Bend field/G1-add tables lack corresponding JSON series. `bend2/bench/box_results.md:4` points at logs on the now-destroyed box. Do not call these tables backed by retained raw samples.

## Audit updates: PARTIAL still holds

| Location | Current finding |
|---|---|
| `docs/used-properly-audit.md:24` checklist #3 | F is stale: `prove.bend:30`, `:40`, `:50` implement five MSM entries plus one QAP entry per GPU proof. Change to P. Lines 9, 69, 74, 120 and 134 repeat the obsolete zero-entry claim. Source text has three bang call sites, six dynamic entries. |
| `docs/used-properly-audit.md:35`, `:36` checklist #6 | “No execution path / no backend comparison” is stale: full-prover CPU1/CPU-all/Metal/CUDA rows now carry OK+EQUAL. Under the audit's strict criterion, use partial rather than unconditional P: the exact GPU-entry path with `--gpu off` is not recorded, and largest-size CPU1 coverage remains missing. |
| `docs/used-properly-audit.md:34`, `:37`, `:84` | V2 coverage improved on box sizes 10/12/14/16 across modes; mini K20 v2/default still has no same-config CPU1/Metal row. Keep remaining coverage partials with current evidence. This audit already reviewed MSM v2 (`:13`, `:22`): the v2 change does not invalidate the serial-join/scan or array-copy findings. |
| `docs/used-properly-audit.md:21`, `:22`, `:23`, `:24`, `:32` | Still applicable: copying array boundaries; serial bucket joins/scans; serial CSR/scalar passes; serialized top-level phases; non-tail loader continuation. Full prover also allocates buckets for padded empty point leaves (`:59`). These support PARTIAL after the GPU switch. |
| `docs/used-properly-audit.md:95`, `:107`, `:104` | Loader-wrap finding remains TRUE, not stale; test runner omissions and NTT failure-exit assertions at line 104 were fixed in a later revision. `Groth.g2_store` workaround remains despite the actual G2 store fix. |

## Stale documentation / maintainability

| Location | Finding |
|---|---|
| `README.md:3`, `:8`, `:9` | Entry README still calls the prover HVM2, sends users to `bend/` for implementation, and omits gnark/Bend 2. `bend/` is now legacy probes; implementation is `bend2/`. Add the actual prove/test command and current results link. |
| `bend2/README.md:14`, `:15`, `:37`, `:49` | Layout/API section predates MSM/NTT/prover; field-only test list no longer describes `run.sh`; “wave 2 builds” language remains. `FORMAT.md:33` promises exactly three stdout lines, but `prove.bend:158` emits T lines too. `tools/README.md:10` pipes unfiltered prover output to a parser that rejects T lines; actual `prove.sh` filters them. |
| `bend2/prove.bend:4`; `bend2/src/groth16.bend:290` | Remove “flip imports when real modules land” and fixed-bug workaround claims. `Groth.g2_store` duplicates the now-correct `G2Aff.to_array` and exists only for that obsolete workaround. |
| `bend2/src/naive.bend:1`; `bend2/scripts/gen_naive_consts.py:1`; `bend2/gen/vectors_to_bin.py:1` | Temporary stand-ins and fallback converter remain. No checked-in caller/test imports naive.bend; either retain as an explicitly exercised oracle or remove it and its helper. Canonical exporter already replaces the fallback. |
| `bend2/src/fq.bend:2476`, `:2482`, `:2490`; `bend2/gen/gen_field.py:263` | Fq shift/limb/bit-window helpers remain uncalled outside their own helper chain; generator still emits them. This residual was not fully removed. Generated 2500-line field files themselves are explained by straight-line CIOS/inversion generation, not an unexplained abstraction problem. |
| `docs/bend2-idioms.md:133`, `:135`, `:165` | These are old proposed designs/estimates: per-window GPU dispatch and parallel bucket joins/prefix reduction are not the implemented MSM; recursive DIT/twiddle-array NTT is not the implemented Stockham chunk tree. The 0.1–0.5 s Metal MSM estimate missed per-window work and is contradicted by measured seconds. Label as superseded plan and link actual modules/results. |
| `docs/bend2-idioms.md:65`, `:100` | G1 affine points occupy 32 U32 limbs, not the example's eight: 2^18 points require 32 MiB, not 8 MiB. The warning about +sharing a proving-key Array conflicts with the actual rule that Array is non-reusable (`:103`; installed GUIDE.md:183). |
| `bend2/bench/msm_results.md:8`, `:51`, `:83` | First tables need an explicit v1 heading; current defaults are v2. “First n points / files exactly fill” is false (loader defect). Attributing OOM to “no GC” omits affine freeing/recycling; private dense bucket memory is the demonstrated issue. |
| `bend2/bench/box_results.md:59`, `:61`; `docs/box.md:8`, `:96` | Box results are an old snapshot, but current-facing future instructions still predict a huge speedup, say MSM/NTT absent, and imply a live rental. The box no longer exists. Keep snapshot provenance while linking current results and teardown state. |
| `docs/comparators.md:196`, `:203`, `:259` | Clearly marked research plan, but not the implemented recipe: arkworks 0.6 proposed versus 0.5 used; gnark GPU recipe only builds BN254 whereas actual runner links all four curves (`comparators/box/build.sh:14`); final comparison table still says Bend/HVM2. Add a current-results/recipe pointer rather than treating these as run instructions. |
| `docs/comparators.md:89`, `:103`, `:195` | Plan download/build recipes were superseded by actual findings: Hermez URLs 403; Mac rapidsnark make target expects unavailable nproc. Actual Circom README documents working alternatives. |
| `comparators/gpu/icicle-prim/Cargo.toml:6` | Claims ICICLE_RS override, but dependency paths are hardcoded `/root/dev/open-icicle/...`; no environment override is read. Box-only build works in its specified layout; advertised relocation does not. |
| `comparators/circom/README.md:99` | hardware_concurrency-based thread count is runtime-derived, not “fixed at build time”. Both Circom Python `--threads` options are labels only. |

## Other harness / repository findings

| Location | Finding |
|---|---|
| `ref/src/bench.rs:156`; `comparators/gnark/main.go:271` | Documented `--max-log2` below 20 produces a scalar array smaller than 2^20, then field-mul benchmark slices 2^20 unconditionally: panic after finishing the selected primitives, before saving their results. |
| `ref/src/bench.rs:27`; `comparators/gnark/main.go:64` | With an even user-specified iteration count, these return the upper middle sample, unlike the midpoint median used by other harnesses. Stored default rows use odd counts, so current JSON is unaffected. |
| `comparators/gnark/main.go:72` | Load sampling is macOS-only sysctl; Linux use records an empty loadavg. Box uses a separate runner with no load sample at all. |
| `.gitignore:1` | Covers targets, node_modules, large proving artifacts and /data. Does not cover documented root-output Bend executables or their .gpu caches, GPU Go binary, Python __pycache__. No such binaries/data were tracked at reviewed HEAD; largest tracked blobs are ~106 KB generated Bend source. Small probe output files are useful evidence, not large artifacts. |
| `_typos.toml:6` | JSON benchmarks entirely excluded from spelling checks; reasonable for machine data, but it also skips free-text notes. No typos process run (quiet-host restriction); static diff check reports only MSM's final blank line. |
| `docs/box.md`; `comparators/box/*.sh` | Rental-specific host details were removed and script paths made variables (`REPO`, `DEV`, `ART`, `TOOLS`). Targeted secret-pattern scan found no committed key/token material. |
| Tracked source/docs | No TODO/FIXME/HACK/XXX markers found. No repo changes staged or left unstaged by this review. |

## Full-prover integer presentation differences

Harmless precision differences, not failed measurements: table values mostly truncate half milliseconds; two round upward. Below, paths are JSON keys (`total` means `ms`; other fields mean `phases_ms.<field>`). All sample lists match. Ordinary decimal rounding in other tables is not a mismatch.

| prover_results.md line | JSON file / parent key | Table -> JSON |
|---|---|---|
| 28 | bench/bend2-macmini.json: prove.18.cpu_all | evals: 163 -> 163.5; msm_b2: 13808 -> 13808.5; msm_h: 5919 -> 5919.5; total: 33491 -> 33491.5 |
| 31 | bench/bend2-macmini.json: prove.14.gpu | load: 52 -> 52.5; msm_a: 4025 -> 4025.5; msm_b1: 4029 -> 4029.5; msm_h: 4461 -> 4461.5; total: 35047 -> 35047.5 |
| 48 | bench/bend2-macmini.json: prove_v1.18.cpu_all | load: 756 -> 756.5; msm_b1: 14285 -> 14285.5; msm_l: 8901 -> 8901.5 |
| 58 | bench/bend2-box.json: prove.18.cpu_all | load: 883 -> 883.5; evals: 239 -> 239.5; msm_a: 4729 -> 4729.5; msm_h: 5075 -> 5075.5; total: 34906 -> 34906.5 |
| 59 | bench/bend2-box.json: prove.20.cpu_all | evals: 926 -> 926.5; qap: 2665 -> 2665.5; msm_b2: 51602 -> 51602.5; msm_h: 16476 -> 16476.5; msm_l: 8980 -> 8980.5; total: 115003 -> 115003.5 |
| 62 | bench/bend2-box.json: prove.18.gpu | qap: 1731 -> 1731.5; msm_a: 8720 -> 8720.5; msm_b2: 21709 -> 21709.5; msm_l: 4809 -> 4809.5 |
| 63 | bench/bend2-box.json: prove.20.gpu | msm_b2: 77240 -> 77240.5; load: 3898 -> 3897.5; msm_l: 18598 -> 18597.5 |
| 76 | bench/bend2-box.json: prove_v1.18.cpu_all | load: 885 -> 885.5; msm_b1: 4220 -> 4220.5; msm_b2: 13694 -> 13694.5; msm_l: 2955 -> 2955.5; total: 31638 -> 31638.5 |
| 77 | bench/bend2-box.json: prove_v1.20.cpu_all | load: 3493 -> 3493.5; msm_a: 13942 -> 13942.5; msm_b1: 13858 -> 13858.5; msm_b2: 45371 -> 45371.5 |

