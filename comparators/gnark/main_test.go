package main

import (
	"math/big"
	"testing"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/frontend/cs/r1cs"
)

// SquareChain(N) has exactly N constraints and the public output is really constrained:
// the correct y solves, y+1 does not.
func TestSquareChain(t *testing.T) {
	const n = 16
	ccs, err := frontend.Compile(ecc.BN254.ScalarField(), r1cs.NewBuilder, &SquareChain{N: n})
	if err != nil {
		t.Fatal(err)
	}
	if got := ccs.GetNbConstraints(); got != n {
		t.Fatalf("constraints %d != %d", got, n)
	}
	y := big.NewInt(3)
	for i := 0; i < n; i++ {
		y.Mul(y, y).Mod(y, ecc.BN254.ScalarField())
	}
	solve := func(y *big.Int) error {
		w, err := frontend.NewWitness(&SquareChain{X0: 3, Y: y, N: n}, ecc.BN254.ScalarField())
		if err != nil {
			t.Fatal(err)
		}
		_, err = ccs.Solve(w)
		return err
	}
	if err := solve(y); err != nil {
		t.Fatalf("correct y rejected: %v", err)
	}
	if err := solve(new(big.Int).Add(y, big.NewInt(1))); err == nil {
		t.Fatal("wrong y accepted")
	}
}
