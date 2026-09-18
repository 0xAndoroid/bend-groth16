//go:build !icicle

package main

import (
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/constraint"
)

func newIciclePK() groth16.ProvingKey { panic("built without -tags=icicle") }

func icicleProve(constraint.ConstraintSystem, groth16.ProvingKey, witness.Witness, bool) (groth16.Proof, error) {
	panic("built without -tags=icicle")
}
