# STAT-REG-006 parameter, covariance and rank verification

## Original program and source

Read this ticket's README, complete original program, expected listing, expected
status/diagnostics, reference log, and SAS/STAT 15.4 physical pp.8617–8619,
8623–8624 and 8649–8650. No implementation or expected-fixture edit is needed for
the verified path. No new tests duplicate the independent checks already in the gate.

The original was executed independently, not accepted from a matching case name.
It fits SASHELP.CLASS Weight on Height, then the 22-row Population model on Year,
adds its precomputed YearSq, and fits Year/YearSq explicitly again. It has no FREQ,
WEIGHT, NOINT or restrictions. Its two Population Output Statistics residual sums
therefore have the same proven intercept identity, with the matrix/data reconstructed
from this source by the existing Fraction-arithmetic verifier.

The original result is rc 1 as expected, with both required warnings matched.
All 1,116 other output tokens are exact after whitespace normalization. Only the
two Sum of Residuals values use the established source-derived bounds:
7.261130843592319e-11 (linear) and 1.7845359484002278e-9 (quadratic), separately
around analytic zero for SAS and OpenSAS. Strict whitespace equality is false;
tolerant acceptance is explicitly recorded in `numeric-verification.json`.
No new tolerance or field exclusion has been introduced.

```sh
python3 tests/STAT15.4-oracle/STAT-REG-002/verify_numeric_contract.py \
  --oracle-dir tests/STAT15.4-oracle/STAT-REG-006 --case documented_feature \
  --report tests/STAT15.4-oracle/STAT-REG-006/numeric-verification.json
zig build gate --cache-dir .zig-cache/reg005 -j2 --summary all
```

The cache argument reuses dev1's working cache after the earlier manager cleanup;
it changes neither source nor build options. Gate results are reported only from
a distinct successful process exit, never inferred from an old or failed log.

## Independent calculations already exercised by the gate

- `reg_fit.zig`, "REG independent hand calculation and inference": for x=(0,1,2),
  y=(1,2,2), beta=(7/6,1/2), SSE=MSE=1/6, error DF=1. Covariance is
  [[5/36,-1/12],[-1/12,1/12]], F=3, slope p=1/3, R-square=3/4 and adjusted
  R-square=1/2. This is a manual small-sample reference, not fitted oracle output.
- `reg_fit.zig`, "REG COMMON-001 and COMMON-003 retained rank covariance and
  inference": the x/twice=2*x/z design has rank 3 and error DF 9. The later
  dependent column is zeroed, its SE is missing, x is marked biased, and all
  retained covariance entries and fitted values equal the reduced full-rank fit.
- `reg_diagnostics.zig`, full-rank inverse/projection and weighted reflexive-inverse
  checks: independent matrix products check AGA=A, GAG=G, reconstruction,
  projection idempotence, trace(P)=rank, and weighted self-adjointness.
- The same module's scaled-alias test preserves legitimate small original-unit
  alias coefficients; its near-collinearity test uses the analytic pivot
  epsilon²/(1+epsilon²), tests both sides of SINGULAR=1e-9 and a custom threshold,
  and checks predictor/common-weight scaling. Ill-conditioned identity checks
  use their stated conditioning-dependent bounds, not an oracle-wide epsilon.
- Malformed/nonfinite inputs, all-zero/zero-rank designs, saturated and
  underdetermined models, zero-weight observations and disagreement with the QR
  precision floor have explicit tests. Numerical failure is not converted to
  successful output.
- `reg_outest.zig`, exact rational covariance test: independent X'WX is
  [[16,104,46],[104,864,366],[46,366,164]], beta=(431/296,2693/1480,237/370),
  SSE=5213/370 and MSE=5213/3330. It checks every covariance entry and verifies
  stored values retain precision beyond the listing. Other existing tests check
  FREQ versus precision-weight DF and response/common-weight covariance scaling.
- Existing Population prediction checks cover t critical values, fitted-value
  variance and confidence/prediction limits; the separate f128/unit/centering
  regression checks residual orthogonality across 24 transformed fits.

The guide describes SAS's sweep implementation. OpenSAS reuses scaled QR and
ordered auxiliary regressions to implement the documented pivot-versus-CSS rank
policy; it does not claim to reproduce SAS's floating-point operation order.
The generalized inverse tested here is reflexive (g2), not a Moore-Penrose claim.

## Degenerate original-program boundary

Because this ticket's supplied program is full rank, the existing unchanged
`STAT-COMMON-003/rank_deficient_regression.sas` was separately executed as a relevant
boundary. Its entire listing matches all 167 expected tokens with whitespace-only
normalization, rc is 0, and stderr is empty. No numeric tolerance is used.

This includes the rank-deficiency explanation, the complete `twice = 2 * x`
relation, x marked B, twice DF0/estimate0/missing SE/t/p, and the remaining estimates,
ANOVA, TOL and VIF fields. The separate `rank-boundary-verification.json` records
that actual execution and hashes; it does not claim another ticket was newly worked.

This verification does not infer support for unexercised named MODEL output
options merely because their underlying coefficient/covariance quantities exist.
