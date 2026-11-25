# REG-002: a quantity-specific residual-sum contract

## Scope and strict comparison

Run the unchanged `documented_default.sas` through the actual CLI. Its expected
status is 1; its two PLOTS/ODS GRAPHICS warnings must match the supplied diagnostic
fixture exactly. Additional emitted NOTE messages must occur in the supplied
reference log. The full actual stderr is retained in the verification receipt;
SAS source echoes, page counts and session notes are not claimed byte-identical.

All 1,118 output tokens are retained and checked. Whitespace is normalized.
Exactly two scalar values can use the numerical rule below: the `Sum of Residuals`
lines in the Population Output Statistics sections for MODEL1 and MODEL1.1.
Their headings, positions, model names, dependent-variable names and multiplicity
are checked. All other tokens—including all coefficients, SEs, tests, probabilities,
confidence limits, individual residuals, Cook's D, PRESS, missing markers, and
ASCII residual charts—must match exactly. No tolerance is applied to them.

The verifier reports both strict whitespace equality (false for this case) and
acceptance under this explicitly disclosed numerical contract. It never rewrites
the expected fixture or the interpreter's output. REG-001's board status is not
changed by this evidence.

## Independent target

Let X contain an intercept and either Year or Year and YearSq. The decimal
population inputs, Year sequence and division by 1000 are read from the original
SAS source. A small **test-only** Fraction-arithmetic normal-equation solve computes
beta-star exactly; it neither calls nor replaces OpenSAS's QR fitter. Exact rational
arithmetic verifies every component of X' (y - X beta-star) is zero.

In particular, because the intercept column is all ones,

    sum(r-star) = 0.

This is true for both models. Therefore the reference's nonzero quadratic residual
sum is itself a floating-point artifact, not a nonzero mathematical target. Its
particular trailing digits must not be copied into the implementation.

## Derived evaluation envelope

Use binary64 unit roundoff u = 2^-53 and gamma(k) = k*u/(1-k*u). For each row define

    w_i = |y_i| + sum_j |X_ij * beta-star_j|
    e_i = gamma(2*p + 2) * w_i
    E   = sum_i e_i
    R   = sum_i |r-star_i|
    B   = E + gamma(n-1) * (R + E).

Here p includes the intercept. The first term budgets rounding while representing
inputs/coefficients, multiplying and adding p prediction terms, and subtracting
the prediction from the response. The 2*p+2 operation budget conservatively covers
these scalar evaluation paths without relying on compensated summation. If each
stored residual differs from its exact-reference counterpart by at most e_i, its
absolute sum is at most R+E. The standard sequential-addition bound then gives the
second term. The oracle sums only residuals; it does not require a relative error
against zero, which would be undefined.

This is an **evaluation-scale acceptance budget for this invariant**, not a theorem
that any QR implementation must satisfy it. QR coefficient error is not inserted
into the budget after observing the result: doing that could excuse a wrong fit.
The implementation must actually satisfy the independent bound, and the regression
below separately checks its predictions and normal-equation defects against a
higher-precision reference. Ill-conditioned failures outside this budget remain
failures. This contract does not authorize tolerances for other fields or models.

The envelope also measures cancellation. W/sum|y| is approximately 51.57 for the
linear fit and 964.87 for the raw quadratic fit. Raw Year/YearSq coefficients create
large opposing terms even though fitted populations are modest. Changing predictor
units without centering leaves the products X_ij*beta_j and this envelope invariant;
centering reduces their cancellation. Scaling the response scales the bound.

The exact source-derived bounds, calculated before reading either output tail, are:

| Model | n | p | W | R | Absolute bound B |
|---|---:|---:|---:|---:|---:|
| Linear | 22 | 2 | 107382.13120496894 | 463.416 | 7.261130843592319e-11 |
| Quadratic | 22 | 3 | 2009103.8050512422 | 40.02019424054207 | 1.7845359484002278e-9 |

Both the SAS value and the OpenSAS value must independently lie in [-B,+B] around
analytic zero. No bound is selected from their observed difference. The verification
JSON includes exact coefficient fractions, exact bound fractions, both observed
values, and whether tolerant acceptance was used.

## Regression and rejection controls

`src/stat/reg_orthogonality_tests.zig`, imported by a test block in `reg_render.zig`,
runs 24 fits: linear/quadratic; raw Year, Year in two power-of-two unit systems,
and centered Year; and three power-of-two response scales. Dyadic transformations
avoid introducing new decimal input-conversion noise. It uses independent f128
normal equations for these tiny test matrices only. It checks:

- each QR fitted value against its higher-precision prediction with the row's e_i;
- all normal-equation components, not just the intercept sum;
- that the f128 reference's own normal-equation defect is negligible compared with
  the binary64 budget;
- rejection of a four-budget defect at every tested scale.

For predictor column j, the normal-equation check weights e_i by |X_ij| and uses
an accumulation allowance gamma(2*n) for multiplication and addition. For the
intercept it uses the same gamma(n-1) residual-sum bound as the oracle verifier.
No production arithmetic, renderer output, REG parser or fitter is changed.

The Python verifier additionally rejects seven mutated listings: out-of-bound
residual sum, missing/extra sum field, missing marker in the sum, renamed parameter,
one changed ANOVA numeric token, and a missing table heading. These protect against
an accidentally broad or field-dropping comparator.

## Reproduction and sources

From the repository root, after building the CLI:

```sh
python3 tests/STAT15.4-oracle/STAT-REG-002/verify_numeric_contract.py \
  --report tests/STAT15.4-oracle/STAT-REG-002/numeric-verification.json
zig build gate --summary all
```

The source is SAS/STAT 15.4 User's Guide physical pp.8540–8558, especially the
Population input and interactive linear/quadratic fits (printed pp.8534–8544).
The independent normal-equation identity follows by differentiating
||y-X beta||^2 at its minimizer; no oracle tail is needed for the derivation.
Gamma(k) is obtained by bounding products of k rounding factors (1+delta),
|delta|<=u; no platform-specific fitted result is assumed.
