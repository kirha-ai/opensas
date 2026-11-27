# REG test reference mathematics

These formulas are used by `src/stat/reg_persistence_tests.zig` and the
`persist_reg_*` corpus fixtures. They depend on the SAS input data, not measured
differences from an implementation. The source is SAS/STAT 15.4, Chapter 105:
Getting Started (physical pp.8540–8558), WEIGHT and OUTEST/COVOUT (8599–8607),
and ridge computations/example (8648–8649, 8719–8723). Linear model moments
are in Chapter 4 (65–80). There is no random sampling or seed normalization.

## Population residual sums

The complete common executable body of REG001, REG002, REG003, REG004 and
REG006 is `tests/corpus/persist_reg_population.sas`; only their descriptive
ticket comments were consolidated. The distinct BY program is retained in
`persist_reg_reg001_statement_by.sas`. All input observations, options and
statements are retained. Full whitespace token sequences preserve the original
expected output except the following two explicitly named scalar fields.

For the 22 decimal populations divided by 1000, let X have columns (1,Year)
or (1,Year,Year²), with Year=1790,1800,...,2000. Test-only reduced i256 rational
arithmetic computes G=(X'X)^-1, beta=G X'y and r=y-X beta, and verifies **every**
component of X'r is exactly zero. In particular sum(r)=0. Production continues
to use scaled QR; no reference solver is used in production.

Let u=2^-53 and gamma(k)=ku/(1-ku). Define

```
W = sum_i (|y_i| + sum_j |X_ij beta_j|)
R = sum_i |r_i|
E = gamma(2p+2) W
B = E + gamma(n-1) (R+E)
```

The first term budgets input/coefficient representation, p prediction products
and additions, and response subtraction; the second budgets sequential residual
summation. This is an invariant acceptance budget for these data, not a claim
that every ill-conditioned QR fit attains it. The independent 24 scaled/centered
fits in `reg_orthogonality_tests.zig` also check each prediction and all normal
equation components, so cancellation alone cannot conceal a wrong fit.

For the linear model W=107382.13120496894, R=463.416 and
B=7.261130843592319e-11. For the quadratic model W=2009103.8050512422,
R=40.02019424054207 and B=1.7845359484002278e-9. Only the
`Sum of Residuals` values in Population Output Statistics for MODEL1 and
MODEL1.1 use `0~B`. Their original values (0 and -4.4596E-11) both lie within
the respective independent zero bounds. All other tokens remain exact.
Tests pin the fields' contexts, multiplicity, model/dependent names and both
persisted tolerances, and reject out-of-bound/missing/extra sums, missing values,
renamed parameters, changed ANOVA numbers and deleted headings.

The full stderr contract retains the two disabled-graphics warnings and the
intervening ADD notes, in order: `Variable YearSq is added.` and
`Due to an ADD statement, the model label is now MODEL1.1.` Both note bodies
occur verbatim in the original SAS reference logs. OpenSAS emits the notes
at the ADD token's location (`reg.zig` Session.edit); for the macro-expanded
interactive slice that location is `NOTE(expanded L2):`. The warning producer
uses location zero (`reg_parse.zig`), so its prefix is exactly `WARNING:`.
The corpus compares this entire four-message stderr sequence, including these
location prefixes; it does not discard notes or allow extra diagnostics.

## Weighted coefficient and covariance output

The complete COMMON004 SAS input lives in
`tests/corpus/persist_reg_common004_weighted_linear_moments.sas`.
`common004_original.txt` is its SAS expected listing with trailing whitespace
trimmed only (all tokens unchanged), shared by
the precision and identity tests; it is not implementation output.
The 94 REG listing tokens and every PRINT header, row identity, missing marker
and dependent-variable cell are exact. Only 16 BEST32 values (RMSE and three
parameters in each of four rows) use numerical bounds.

For the input's 12 observations and three columns, exact arithmetic gives

```
A = X'WX = [[16,104,46],[104,864,366],[46,366,164]]
beta = (431/296,2693/1480,237/370)
SSE = 5213/370; m = MSE = 5213/3330
G = inverse(A); C = m G
C = [[224159/438080, -57343/3942720, -36491/328560],
     [-57343/3942720, 662051/19713600, -349271/4928400],
     [-36491/328560, -349271/4928400, 245011/1232100]]
```

The tests rederive these from the corpus DATALINES and check AG=I, A beta=X'Wy
and X'Wr=0 in exact rational arithmetic. Conversion to f128 uses two u128 limbs
to avoid unsupported LLVM i256 float conversion. The subsequent budget
evaluation uses f128, whose rounding is negligible at the binary64 budgets.

Componentwise bounds (all scales use the independent reference) are

```
d_i = gamma(6p+2) (|y_i| + sum_j |X_ij beta_j|)
E_j = sum_i |w_i X_ij| d_i
      + gamma(7n+2) (sum_i |w_i X_ij r_i| + sum_i |w_i X_ij| d_i)
B_j = sum_k |G_jk| E_k
q_i = sum_j |X_ij| B_j
Q = B' |A| B
T = sum_i w_i (2 (|r_i|+q_i) d_i + d_i²)
S = Q + T + gamma(8n+2) (SSE+Q+T)
M = S/(n-p) + gamma(1) m
R = M/(sqrt(m)+sqrt(m-M)) + gamma(1) sqrt(m)
H_kj = gamma(6p+2) (sum_l |A_kl C_lj| + m delta_kj)
V_ij = sum_k |G_ik| H_kj + |G_ij| M + gamma(1) |C_ij|
```

The operation counts allow one product and up to five compensated accumulation
operations per term, two final conversion/subtraction operations, an additional
weight multiplication in the normal product, and eight operations per weighted
squared residual. X'Wr=0 cancels the first-order coefficient perturbation in
SSE; inverse propagation retains componentwise conditioning rather than applying
a blanket relative tolerance. These are acceptance budgets, not universal QR
forward-error guarantees.

For each printed cell, add half the last decimal unit of the **immutable SAS
cell** to its B_j, V_ij or R. Corpus targets are the independent exact fraction
(80-decimal-digit square root for RMSE), not the observed SAS or OpenSAS value.
The tests check every persisted target and bound against their own derivation.
Both original SAS and actual BEST32-formatted OUTEST values must satisfy these
bounds; actual printed precision cannot be reduced to enlarge the allowance.
Separate printed-value certificates check A beta=b and AC=mI, including all
off-diagonal entries, with only the reference decimal quantization propagated.
Mutation checks reject wrong model/type, removed type, changed covariance,
coarsened precision and corruption of every covariance entry.

## Ridge data contracts

`ridge_original.sas` is the complete original REG005 input. Its data and both
PROC REG statements feed the default unit test; it is not a passing listing
golden. Existing `reg_ridge.zig` tests independently check the orthogonal k=0/1
solutions and transformations. The persistence test checks 23/12 OUTEST rows,
13 columns, identities/missingness, all 11 constants and stored coefficients,
VIF and RMSE against all ridge metadata points, plus five SVG objects, panel
counts, series counts and residual-point counts. For every point it independently
reevaluates source-row residuals and checks SSE and RMSE²=SSE/(16-6). The 1e-10
relative cross-check budgets cancellation when recovering residuals from raw
temperature and temperature-squared coefficients; it is not a tolerance on a
SAS expected listing. Five-graph visual equivalence, a complete independent
acetylene ridge-path solution and IPC are not asserted by these checks.
