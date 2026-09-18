// gnark-bench: Groth16 (BN254) prover and primitive timings for the SquareChain(N)
// comparator. See README.md for commands and docs/comparators.md for the recipe.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/big"
	"os"
	"os/exec"
	"runtime"
	"runtime/debug"
	"sort"
	"strings"
	"time"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark-crypto/ecc/bn254"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr/fft"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/constraint"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
	"github.com/consensys/gnark/logger"
)

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// SquareChain: private x0, x_{i+1} = x_i^2, public Y = x_N. Exactly N constraints:
// N-1 api.Mul rows plus one raw R1C (x_{N-1} * x_{N-1} == Y), because
// AssertIsEqual(Mul(x,x), Y) would emit two rows.
type SquareChain struct {
	X0 frontend.Variable
	Y  frontend.Variable `gnark:",public"`
	N  int               `gnark:"-"`
}

func (c *SquareChain) Define(api frontend.API) error {
	x := c.X0
	for i := 0; i < c.N-1; i++ {
		x = api.Mul(x, x)
	}
	cp := api.Compiler()
	bp := &constraint.BlueprintGenericR1C{}
	id := cp.AddBlueprint(bp)
	a := cp.ToCanonicalVariable(x).(constraint.LinearExpression)
	out := cp.ToCanonicalVariable(c.Y).(constraint.LinearExpression)
	var data []uint32
	bp.CompressR1C(&constraint.R1C{L: a, R: a, O: out}, &data)
	cp.AddInstruction(id, data)
	return nil
}

func median(xs []float64) float64 {
	s := append([]float64(nil), xs...)
	sort.Float64s(s)
	return s[len(s)/2]
}

func ms(d time.Duration) float64 { return float64(d.Nanoseconds()) / 1e6 }

func now() string { return time.Now().UTC().Format(time.RFC3339) }

// timeN runs f iters times and returns the samples in ms.
func timeN(iters int, f func()) []float64 {
	out := make([]float64, 0, iters)
	for i := 0; i < iters; i++ {
		t := time.Now()
		f()
		out = append(out, ms(time.Since(t)))
	}
	return out
}

func defaultIters(log2 int) int {
	switch {
	case log2 <= 14:
		return 5
	case log2 <= 18:
		return 3
	default:
		return 1
	}
}

func prove(log2, iters int) map[string]any {
	n := 1 << log2
	if iters == 0 {
		iters = defaultIters(log2)
	}
	t := time.Now()
	ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &SquareChain{N: n})
	check(err)
	compileMs := ms(time.Since(t))
	if got := ccs.GetNbConstraints(); got != n {
		check(fmt.Errorf("constraint count %d != %d", got, n))
	}
	t = time.Now()
	pk, vk, err := groth16.Setup(ccs)
	check(err)
	setupMs := ms(time.Since(t))

	y := big.NewInt(3)
	for i := 0; i < n; i++ {
		y.Mul(y, y).Mod(y, ecc.BN254.ScalarField())
	}
	w, err := frontend.NewWitness(&SquareChain{X0: 3, Y: y, N: n}, ecc.BN254.ScalarField())
	check(err)
	pub, err := w.Public()
	check(err)

	// warm-up (not counted), verified
	proof, err := groth16.Prove(ccs, pk, w)
	check(err)
	check(groth16.Verify(proof, vk, pub))

	// witness solver alone (Prove re-runs it internally; solve_ms is a separate measurement,
	// not subtracted from ms)
	solve := timeN(iters, func() { _, err := ccs.Solve(w); check(err) })

	samples := make([]float64, 0, iters)
	for i := 0; i < iters; i++ {
		t := time.Now()
		proof, err := groth16.Prove(ccs, pk, w)
		samples = append(samples, ms(time.Since(t)))
		check(err)
		check(groth16.Verify(proof, vk, pub))
	}
	return map[string]any{
		"log2": log2, "num_constraints": n, "num_wires": ccs.GetNbInternalVariables() + ccs.GetNbSecretVariables() + ccs.GetNbPublicVariables(),
		"num_public": ccs.GetNbPublicVariables(), "qap_domain": n,
		"ms": median(samples), "iters": iters, "samples_ms": samples,
		"solve_ms": median(solve), "solve_samples_ms": solve,
		"compile_ms": compileMs, "setup_ms": setupMs,
		"pk_source": "in-memory setup", "verified": true,
		"threads": runtime.GOMAXPROCS(0), "timestamp": now(),
	}
}

func randScalars(n int) []fr.Element {
	s := make([]fr.Element, n)
	for i := range s {
		_, err := s[i].SetRandom()
		check(err)
	}
	return s
}

// g1Points: p_0 = g, p_i = 2 p_{i-1} + g (distinct, cheap to build), batch-normalized.
func g1Points(n int) []bn254.G1Affine {
	_, _, g, _ := bn254.Generators()
	jac := make([]bn254.G1Jac, n)
	jac[0].FromAffine(&g)
	for i := 1; i < n; i++ {
		jac[i].Double(&jac[i-1]).AddMixed(&g)
	}
	return bn254.BatchJacobianToAffineG1(jac)
}

func g2Points(n int) []bn254.G2Affine {
	_, _, _, g := bn254.Generators()
	jac := make([]bn254.G2Jac, n)
	jac[0].FromAffine(&g)
	for i := 1; i < n; i++ {
		jac[i].Double(&jac[i-1]).AddMixed(&g)
	}
	out := make([]bn254.G2Affine, n)
	for i := range out {
		out[i].FromJacobian(&jac[i])
	}
	return out
}

func primIters(log2 int) int {
	if log2 <= 16 {
		return 5
	}
	return 3
}

func entry(log2 int, samples []float64, threads int) map[string]any {
	return map[string]any{"log2": log2, "ms": median(samples), "iters": len(samples),
		"samples_ms": samples, "threads": threads, "timestamp": now()}
}

func primitives(maxLog2 int) map[string]any {
	all := runtime.GOMAXPROCS(0)
	res := map[string]any{"msm_g1": map[string]any{}, "msm_g1_1t": map[string]any{},
		"msm_g2": map[string]any{}, "msm_g2_1t": map[string]any{},
		"ntt": map[string]any{}, "ntt_1t": map[string]any{}}
	set := func(key string, log2 int, v any) { res[key].(map[string]any)[fmt.Sprint(log2)] = v }

	fmt.Fprintln(os.Stderr, "generating 2^"+fmt.Sprint(maxLog2)+" G1 points / scalars")
	p1 := g1Points(1 << maxLog2)
	sc := randScalars(1 << maxLog2)
	for k := 10; k <= maxLog2; k++ {
		n := 1 << k
		var r bn254.G1Jac
		for _, cfg := range []struct {
			key   string
			tasks int
		}{{"msm_g1", all}, {"msm_g1_1t", 1}} {
			f := func() { _, err := r.MultiExp(p1[:n], sc[:n], ecc.MultiExpConfig{NbTasks: cfg.tasks}); check(err) }
			f() // warm
			set(cfg.key, k, entry(k, timeN(primIters(k), f), cfg.tasks))
			fmt.Fprintf(os.Stderr, "%s 2^%d: %.2f ms\n", cfg.key, k, res[cfg.key].(map[string]any)[fmt.Sprint(k)].(map[string]any)["ms"])
		}
	}
	p1 = nil

	g2max := min(maxLog2, 16)
	fmt.Fprintln(os.Stderr, "generating 2^"+fmt.Sprint(g2max)+" G2 points")
	p2 := g2Points(1 << g2max)
	for k := 10; k <= g2max; k++ {
		n := 1 << k
		var r bn254.G2Jac
		for _, cfg := range []struct {
			key   string
			tasks int
		}{{"msm_g2", all}, {"msm_g2_1t", 1}} {
			f := func() { _, err := r.MultiExp(p2[:n], sc[:n], ecc.MultiExpConfig{NbTasks: cfg.tasks}); check(err) }
			f()
			set(cfg.key, k, entry(k, timeN(primIters(k), f), cfg.tasks))
			fmt.Fprintf(os.Stderr, "%s 2^%d: %.2f ms\n", cfg.key, k, res[cfg.key].(map[string]any)[fmt.Sprint(k)].(map[string]any)["ms"])
		}
	}
	p2 = nil

	// radix-2 FFT over Fr, coset off: FFT = DIF forward, FFTInverse = DIT.
	for k := 10; k <= maxLog2; k++ {
		n := 1 << k
		d := fft.NewDomain(uint64(n))
		a := append([]fr.Element(nil), sc[:n]...)
		for _, cfg := range []struct {
			key   string
			tasks int
		}{{"ntt", all}, {"ntt_1t", 1}} {
			fwd := func() { d.FFT(a, fft.DIF, fft.WithNbTasks(cfg.tasks)) }
			inv := func() { d.FFTInverse(a, fft.DIT, fft.WithNbTasks(cfg.tasks)) }
			fwd()
			inv()
			fs := timeN(primIters(k), fwd)
			is := timeN(primIters(k), inv)
			set(cfg.key, k, map[string]any{"log2": k, "fft_ms": median(fs), "ifft_ms": median(is),
				"iters": len(fs), "fft_samples_ms": fs, "ifft_samples_ms": is, "threads": cfg.tasks, "timestamp": now()})
			fmt.Fprintf(os.Stderr, "%s 2^%d: fft %.3f ms, ifft %.3f ms\n", cfg.key, k, median(fs), median(is))
		}
	}

	// Fr mul throughput, single goroutine.
	const nMuls = 10_000_000
	var x, yv fr.Element
	x.SetRandom()
	yv.SetRandom()
	t := time.Now()
	for i := 0; i < nMuls; i++ {
		x.Mul(&x, &yv)
	}
	dep := float64(nMuls) / time.Since(t).Seconds()
	const batch = 1 << 20
	av, bv, out := sc[:batch], randScalars(batch), make([]fr.Element, batch)
	t = time.Now()
	for i := 0; i < nMuls/batch; i++ {
		for j := range out {
			out[j].Mul(&av[j], &bv[j])
		}
	}
	indep := float64(nMuls/batch*batch) / time.Since(t).Seconds()
	res["fr_mul"] = map[string]any{"dependent_muls_per_sec": dep, "independent_muls_per_sec": indep,
		"n_muls": nMuls, "batch": batch, "threads": 1, "sink": x.String()[:8], "timestamp": now()}
	fmt.Fprintf(os.Stderr, "fr_mul: dependent %.3g/s, independent %.3g/s\n", dep, indep)
	return res
}

func sh(name string, args ...string) string {
	b, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func versions() map[string]string {
	v := map[string]string{"go": runtime.Version()}
	if bi, ok := debug.ReadBuildInfo(); ok {
		for _, d := range bi.Deps {
			if strings.HasPrefix(d.Path, "github.com/consensys/gnark") {
				v[strings.TrimPrefix(d.Path, "github.com/consensys/")] = d.Version
			}
		}
	}
	return v
}

// merge writes result keys into the JSON file at path (creating it), keeping other keys,
// so sizes and subcommands can run as separate processes.
func merge(path string, result map[string]any) {
	doc := map[string]any{}
	if b, err := os.ReadFile(path); err == nil {
		check(json.Unmarshal(b, &doc))
	}
	host, _ := os.Hostname()
	doc["schema"] = 1
	doc["framework"] = "gnark"
	doc["versions"] = versions()
	doc["host"] = strings.ToLower(strings.SplitN(host, ".", 2)[0])
	doc["cpu"] = sh("sysctl", "-n", "machdep.cpu.brand_string")
	doc["threads"] = runtime.NumCPU()
	doc["git_head"] = sh("git", "rev-parse", "--short", "HEAD")
	doc["updated"] = now()
	if _, ok := doc["notes"]; !ok {
		doc["notes"] = "prove.ms = groth16.Prove incl. gnark witness solving; solve_ms = ccs.Solve alone (separate run, not subtracted). *_1t = GOMAXPROCS=1 (prove) / NbTasks=1 (primitives)."
	}
	for k, v := range result {
		sub, isMap := v.(map[string]any)
		old, hadOld := doc[k].(map[string]any)
		if isMap && hadOld && k != "fr_mul" {
			for kk, vv := range sub {
				old[kk] = vv
			}
		} else {
			doc[k] = v
		}
	}
	b, err := json.MarshalIndent(doc, "", "  ")
	check(err)
	check(os.WriteFile(path, b, 0o644))
}

func main() {
	logger.Disable()
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: gnark-bench prove --log2 K [--iters I] [--gomaxprocs T] [--out FILE]\n       gnark-bench primitives [--max-log2 20] [--out FILE]")
		os.Exit(2)
	}
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	log2 := fs.Int("log2", 10, "log2 of constraint count")
	iters := fs.Int("iters", 0, "timed proofs (0 = 5 for K<=14, 3 for K<=18, 1 above)")
	procs := fs.Int("gomaxprocs", 0, "runtime.GOMAXPROCS override")
	maxLog2 := fs.Int("max-log2", 20, "largest primitive size")
	out := fs.String("out", "", "merge results into this JSON file")
	check(fs.Parse(os.Args[2:]))
	if *procs > 0 {
		runtime.GOMAXPROCS(*procs)
	}
	var result map[string]any
	switch os.Args[1] {
	case "prove":
		key := "prove"
		if runtime.GOMAXPROCS(0) == 1 {
			key = "prove_1t"
		}
		result = map[string]any{key: map[string]any{fmt.Sprint(*log2): prove(*log2, *iters)}}
	case "primitives":
		result = primitives(*maxLog2)
	default:
		check(fmt.Errorf("unknown subcommand %q", os.Args[1]))
	}
	if *out != "" {
		merge(*out, result)
	}
	b, err := json.MarshalIndent(result, "", "  ")
	check(err)
	fmt.Println(string(b))
}
