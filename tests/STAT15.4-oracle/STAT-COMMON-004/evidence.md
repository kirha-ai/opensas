# STAT-COMMON-004 implementation and verification

## Result and scope

REG accepts OUTEST= (including two-level names) and COVOUT and publishes the
result only after every BY/model fit succeeds. It writes PARMS and covariance
rows with model identity, dependent-variable identity, covariance row names,
RMSE and full-precision coefficients/covariances. Dependent-variable PARMS
entries are -1; dependent-variable covariance entries and omitted regressors are
missing. BY columns retain source descriptors. NOINT, multiple models, VAR
variables, NOPRINT and the retained rank-deficient fit are covered by tests.

The existing frequency adjustment scales the whole covariance matrix and SEs
using frequency-count degrees of freedom. Precision weights contribute to the
normal equations, not to the observation count. No change to reg_fit.zig or
reg_diagnostics.zig is needed.

Coordinated rendering changes add the missing REG WEIGHT heading and split flat
PRINT reports into balanced contiguous column panels under LINESIZE. All fields,
rows, and observation numbers are retained. Explicit-ID and BY PRINT layout
remains on its existing path; individual oversized columns are not truncated.
The focused panel test covers repeated observation numbers, width that fits,
oversized columns, and the mixed character/BEST32 widths used by this oracle.
No existing corpus golden or original oracle expected file is changed.

The descriptor tests check nine columns in oracle order and four rows, numeric
versus character type, name/type fields and declared lengths. Numeric storage
length is 8; name fields use 32 and _TYPE_ uses 8. The original listing/log expose
names, values, row count and column count, not SAS's declared text lengths. No
new global dataset TYPE= metadata facility is claimed by this change.

## Original oracle and exact comparisons

Run the original, unchanged `weighted_linear_moments.sas`. Expected/actual exit
status is 0/0 and actual stderr is empty, captured without filtering. The complete
94-token REG listing matches exactly after whitespace tokenization, including
WEIGHT identity, every statistic, parameter, degree of freedom and p-value.
Both PRINT panel headers, all four rows, all nine columns, every nonnumeric
field and all missing/dependent-variable cells are compared exactly.

BEST32 is the sole numerical exception: its unrounded values are independently
checked against exact rational references with per-quantity arithmetic budgets
below. Neither side is treated as the numerical truth merely because it is the
oracle. Printed numeric precision cannot be reduced to enlarge an allowance.
The script also checks the normal equations and covariance identity using exact
arithmetic on each side's printed decimal values.

Original expected SHA-256:
`968e7121f1228c7068ecc7202c424a7316f0d4fb446ebeafa824a5af696f7ab4`.

`weighted_linear_moments.actual.txt` preserves the complete OpenSAS listing;
`weighted_linear_moments.raw-token.diff` preserves every difference from SAS.
These are actual/evidence artifacts, not replacement goldens. The largest raw
numeric difference is 8.706e-15. The source interpreter retains its own OpenSAS
version; this oracle does not print runtime identity.

## Independent rational reference

Python Fraction arithmetic reads the actual oracle DATALINES and forms:

```
A = X'WX = [[16,104,46], [104,864,366], [46,366,164]]
beta = (431/296, 2693/1480, 237/370)
SSE = 5213/370
MSE = 5213/3330                    (12 observations - rank 3)
C = MSE * inverse(A)
  = [[224159/438080, -57343/3942720, -36491/328560],
     [-57343/3942720, 662051/19713600, -349271/4928400],
     [-36491/328560, -349271/4928400, 245011/1232100]]
```

The reference inversion and solution are checked with exact A*G=I and A*beta=b.
Only RMSE needs a square root; it is evaluated at 80 decimal digits. Stored
OpenSAS covariance is additionally checked by inline tests against these exact
fractions with absolute error 5e-15, and coefficients with absolute error 5e-14.
These checks are separate from the formatted-output comparison.

## Floating-point error budgets, not observed-difference thresholds

Let u=2^-53 (binary64 unit roundoff, machine epsilon/2) and
`gamma(k)=k*u/(1-k*u)`. Let G=A^-1, r=y-X*beta, m=MSE, C=mG, n=12 and p=3.
Absolute values below are componentwise. All budget scales come from the exact
reference, before examining either output's difference. G carries the conditioning;
`||A||_infinity * ||G||_infinity = 160747/296`.

The operation counts are conservative for the source's compensated accumulation:
one product and at most five additions/subtractions per dot term, plus two
operations for final conversion/subtraction; weighted normal products add a
multiplication; weighted square accumulation allows eight operations per row.
These define strict identity-residual acceptance budgets for this data, not a
promise that every possible ill-conditioned QR input attains the same accuracy.

**Coefficients.** First bound row evaluation and weighted normal-equation
residuals:

```
d_i = gamma(6p+2) * (|y_i| + sum_j |x_ij beta_j|)
E_j = sum_i |w_i x_ij| d_i
      + gamma(7n+2) * (sum_i |w_i x_ij r_i| + sum_i |w_i x_ij| d_i)
B_j = sum_k |G_jk| E_k
```

B is the componentwise forward coefficient budget, obtained from
`delta_beta = G * normal_equation_residual`. It includes the actual design's
conditioning, rather than an arbitrary shared relative tolerance.

**Residual variance and RMSE.** Define `q_i=sum_j |x_ij| B_j` and
`Q=B'|A|B`. The exact identity X'Wr=0 cancels the first-order coefficient
perturbation in residual sum of squares, so:

```
T = sum_i w_i * (2*(|r_i|+q_i)*d_i + d_i^2)
S = Q + T + gamma(8n+2)*(SSE+Q+T)
M = S/(n-p) + gamma(1)*m
R = M/(sqrt(m)+sqrt(m-M)) + gamma(1)*sqrt(m)
```

M and R are the MSE and RMSE budgets. The positive denominator is checked by
high-precision reference evaluation; no estimate is derived from observed error.

**Covariance.** Use the defining identity A*C=mI, with dot-product residual
budget H and componentwise inverse propagation:

```
H_kj = gamma(6p+2) * (sum_l |A_kl C_lj| + m*delta_kj)
V_ij = sum_k |G_ik| H_kj + |G_ij| M + gamma(1)*|C_ij|
```

Each covariance entry has its own V_ij; signs, off-diagonal magnitudes, variance
scale and conditioning are included. The verifier directly checks A*C=mI as well
as each value's distance from its exact reference.

**Decimal display.** Add half the last printed decimal unit of the immutable
SAS reference cell to each arithmetic budget. That same reference resolution
applies to BOTH outputs. OpenSAS may retain more digits but may not print fewer
to inflate its allowance. Missing cells and the dependent-variable -1 are exact.

Measured maximum arithmetic budgets are about 1.037e-12 for coefficients,
9.474e-14 for covariance and 8.962e-14 for RMSE (the JSON records every cell's
unrounded bound). Actual errors against the independent reference are much smaller:

| Family | Largest SAS-reference error | Largest OpenSAS-reference error |
|---|---:|---:|
| Coefficients | 4.595e-15 | 2.560e-15 |
| Covariance | 8.736e-15 | 3.912e-16 |
| RMSE | 1.048e-15 | 2.521e-16 |

## Regression and reproduction

Eight OUTEST tests cover independent weighted and intercept-only calculations,
FREQ versus WEIGHT, covariance scaling, singular models, schema/identity fields,
BY/multiple models/NOINT, malformed output requests, full oracle rational data,
and failed later-group atomic publication. Two focused renderer tests cover PRINT
panels and the weight heading. All are imported in the normal Zig gate.

Run from the repository root:

```sh
zig build gate -j2 --summary all
zig build -j2
python3 tests/STAT15.4-oracle/STAT-COMMON-004/verify.py
```

The verifier preserves raw stdout, raw stderr, a token diff and per-cell JSON in
`.zig-cache/stat-common-004-evidence/`. It rejects five deliberate mutations:
model identity, covariance row identity, covariance value, reduced precision,
and a removed metadata field. It asserts the real subprocess exit status; no
pipeline can mask failure. The pre-rebase gate passed 1653 tests, 2304 corpus
cases and 11 programs. Final rebased counts/SHA are recorded in the delivery report.

A disk-pressure build exited 1 and was not treated as green. After authorized cache
reclamation, the stale build-runner manifest failed with FileNotFound. A distinct
fresh-cache gate then exited 0; later gates use that fresh cache with -j2.

Read sources: SAS/STAT 15.4 physical pages 65–80 and 135–148, plus REG WEIGHT and
OUTEST/COVOUT physical pages 8599–8607; Base Procedures Guide PRINT printed
pp.1777–1778 and 1798–1800; Formats Reference BESTw printed pp.144–145.
