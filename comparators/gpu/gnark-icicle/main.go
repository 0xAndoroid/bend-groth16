// gnark v0.16.3 Groth16/BN254 SquareChain(N) prover benchmark.
// CPU: `go build .`; GPU (icicle-gnark v3.2.2): `go build -tags=icicle .` and pass -gpu.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"math/big"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/constraint"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
)

type SquareChain struct {
	X0 frontend.Variable
	Y  frontend.Variable `gnark:",public"`
	N  int               `gnark:"-"`
}

// Define emits exactly N rows: N-1 Mul rows plus one raw R1C (x*x == Y), because
// AssertIsEqual(Mul(x,x),Y) would emit two rows.
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

func check(err error) {
	if err != nil {
		panic(err)
	}
}

type entry struct {
	Log2           int       `json:"log2"`
	NumConstraints int       `json:"num_constraints"`
	Ms             float64   `json:"ms"`
	Iters          int       `json:"iters"`
	SamplesMs      []float64 `json:"samples_ms"`
	FirstProveMs   float64   `json:"first_prove_ms"`
	SolveMs        float64   `json:"solve_ms"`
	SetupMs        float64   `json:"setup_ms"`
	PkBytes        int       `json:"pk_bytes"`
	Verified       bool      `json:"verified"`
	Gomaxprocs     int       `json:"gomaxprocs"`
	PinToGPU       *bool     `json:"pin_to_gpu,omitempty"`
	Timestamp      string    `json:"timestamp"`
}

type result struct {
	Schema    int               `json:"schema"`
	Framework string            `json:"framework"`
	Versions  map[string]string `json:"versions"`
	Host      string            `json:"host"`
	CPU       string            `json:"cpu"`
	GPU       string            `json:"gpu,omitempty"`
	Threads   int               `json:"threads"`
	GitHead   string            `json:"git_head"`
	Updated   string            `json:"updated"`
	Notes     string            `json:"notes"`
	Prove     map[string]entry  `json:"prove"`
}

func median(xs []float64) float64 {
	s := append([]float64(nil), xs...)
	sort.Float64s(s)
	n := len(s)
	if n%2 == 1 {
		return s[n/2]
	}
	return (s[n/2-1] + s[n/2]) / 2
}

func ms(d time.Duration) float64 { return float64(d.Nanoseconds()) / 1e6 }

func main() {
	ks := flag.String("k", "10,14,18,20", "comma-separated log2 sizes")
	iters := flag.Int("iters", 3, "timed proves per size (after one warm-up)")
	gpu := flag.Bool("gpu", false, "prove with icicle-gnark (requires -tags=icicle build)")
	pin := flag.Bool("pin", false, "icicle: PinToGPU (keep PK vectors resident)")
	out := flag.String("out", "", "JSON output file (merged by log2)")
	cpuName := flag.String("cpu", "", "CPU model string for the JSON")
	gpuName := flag.String("gpu-name", "", "GPU model string for the JSON")
	gitHead := flag.String("git-head", "", "repo HEAD for the JSON")
	flag.Parse()

	res := result{Schema: 1, Framework: "gnark", Versions: map[string]string{"gnark": "v0.16.3", "gnark-crypto": "v0.21.0", "go": runtime.Version()},
		CPU: *cpuName, Threads: runtime.GOMAXPROCS(0), GitHead: *gitHead, Prove: map[string]entry{}}
	res.Host, _ = os.Hostname()
	if *gpu {
		res.Framework = "gnark-icicle"
		res.Versions["icicle-gnark"] = "v3.2.2"
		res.GPU = *gpuName
		res.Notes = "icicleGroth.Prove on gnark rows; time includes gnark witness solving + H2D of witness-dependent vectors (PK vectors pinned only if pin_to_gpu); first_prove_ms includes ICICLE backend load + device warm-up. Proof verified with native gnark VK."
	} else {
		res.Notes = "groth16.Prove (CPU) on gnark rows; time includes gnark constraint solver (solve_ms measured separately via ccs.Solve). Proof verified with gnark VK."
	}
	if *out != "" {
		if b, err := os.ReadFile(*out); err == nil {
			var old result
			if json.Unmarshal(b, &old) == nil && old.Prove != nil {
				res.Prove = old.Prove
			}
		}
	}

	for _, ks := range strings.Split(*ks, ",") {
		k, err := strconv.Atoi(strings.TrimSpace(ks))
		check(err)
		n := 1 << k
		fmt.Fprintf(os.Stderr, "== K=%d N=%d gpu=%v pin=%v GOMAXPROCS=%d\n", k, n, *gpu, *pin, runtime.GOMAXPROCS(0))
		ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &SquareChain{N: n})
		check(err)
		if ccs.GetNbConstraints() != n {
			panic(fmt.Sprintf("constraint count %d != %d", ccs.GetNbConstraints(), n))
		}
		t := time.Now()
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

		t = time.Now()
		_, err = ccs.Solve(w)
		check(err)
		solveMs := ms(time.Since(t))

		var buf bytes.Buffer
		_, err = pk.WriteRawTo(&buf)
		check(err)
		pkBytes := buf.Len()

		prove := func() (groth16.Proof, error) { return groth16.Prove(ccs, pk, w) }
		var pinP *bool
		if *gpu {
			gpk := newIciclePK()
			_, err = gpk.UnsafeReadFrom(&buf)
			check(err)
			prove = func() (groth16.Proof, error) { return icicleProve(ccs, gpk, w, *pin) }
			p := *pin
			pinP = &p
		}

		t = time.Now()
		proof, err := prove()
		first := ms(time.Since(t))
		check(err)
		check(groth16.Verify(proof, vk, pub))
		fmt.Fprintf(os.Stderr, "   first prove %.1f ms (verified); setup %.0f ms; solve %.1f ms; pk %d bytes\n", first, setupMs, solveMs, pkBytes)

		samples := make([]float64, 0, *iters)
		verified := true
		for i := 0; i < *iters; i++ {
			t = time.Now()
			proof, err = prove()
			d := ms(time.Since(t))
			check(err)
			if groth16.Verify(proof, vk, pub) != nil {
				verified = false
			}
			samples = append(samples, d)
			fmt.Fprintf(os.Stderr, "   prove[%d] %.1f ms\n", i, d)
		}
		res.Prove[strconv.Itoa(k)] = entry{Log2: k, NumConstraints: n, Ms: median(samples), Iters: *iters, SamplesMs: samples,
			FirstProveMs: first, SolveMs: solveMs, SetupMs: setupMs, PkBytes: pkBytes, Verified: verified,
			Gomaxprocs: runtime.GOMAXPROCS(0), PinToGPU: pinP, Timestamp: time.Now().UTC().Format(time.RFC3339)}
		fmt.Fprintf(os.Stderr, "   median %.1f ms verified=%v\n", median(samples), verified)
		if !verified {
			panic("proof verification failed")
		}
	}
	res.Updated = time.Now().UTC().Format(time.RFC3339)
	b, err := json.MarshalIndent(res, "", "  ")
	check(err)
	b = append(b, '\n')
	if *out != "" {
		check(os.WriteFile(*out, b, 0o644))
	} else {
		os.Stdout.Write(b)
	}
}
