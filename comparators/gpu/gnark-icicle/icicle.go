//go:build icicle

package main

import (
	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/accelerated/icicle"
	icicleGroth "github.com/consensys/gnark/backend/accelerated/icicle/groth16"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/constraint"
)

func newIciclePK() groth16.ProvingKey { return icicleGroth.NewProvingKey(ecc.BN254) }

func icicleProve(ccs constraint.ConstraintSystem, pk groth16.ProvingKey, w witness.Witness, pin bool) (groth16.Proof, error) {
	return icicleGroth.Prove(ccs, pk, w, icicle.WithPinKeysToGPU(pin))
}
