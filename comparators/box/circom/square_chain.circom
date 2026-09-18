pragma circom 2.1.0;

// Canonical benchmark circuit (FROZEN, identical across frameworks):
//   private input x0; x_{i+1} = x_i * x_i for i in 0..N; public output y = x_N.
// Exactly N R1CS constraints: each `x[i+1] <== x[i] * x[i]` is one quadratic
// constraint; the two linear aliases (x[0] <== x0, y <== x[N]) are eliminated
// by circom's default linear-constraint optimisation (--O1 or higher).
template SquareChain(N) {
    signal input x0;
    signal output y;
    signal x[N + 1];

    x[0] <== x0;
    for (var i = 0; i < N; i++) {
        x[i + 1] <== x[i] * x[i];
    }
    y <== x[N];
}
