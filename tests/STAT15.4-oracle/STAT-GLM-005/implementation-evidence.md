# STAT-GLM-005 — tested foundation; full oracle remains blocked

Read both original programs, complete expected outputs/logs, the ticket/README,
and SAS/STAT 15.4 physical pages 4065 and 4106–4110 (printed 4053,4094–4098).
Also read absorption algorithm/equivalence on physical pages 4124–4125
(printed 4112–4113). Original expected files and input programs are unchanged.

## Actual implementation

`glm_absorb.zig` projects each response and nonabsorbed design column off sorted
nested ABSORB strata using compensated, anchored precision×frequency weighted
means. It does not build a matrix of block dummy variables. Each successive
ABSORB key is nested within its predecessors. Prefix projections produce the
absorbed Type I SS and rank increments. The residual model reuses the existing
QR/GLM helper with no intercept; the absorbed rank is subtracted from residual
space N before computing error DF, MSE, covariance, SE and F/p statistics.
Global model statistics retain the original response mean and corrected total SS.

The absorbed rank R includes the intercept. With residual rank r and frequency
count N, full rank=R+r, error DF=N-R-r, model DF=R+r-1, total DF=N-1. Conditional
covariance is MSE times the within-design generalized inverse. Precision weights
affect projection/crossproducts, while FREQ alone changes N. No coefficient or
variance is fabricated for a zero-DF or saturated fit.

The separate absorption renderer leaves the baseline GLM effect-table renderer
untouched. ABSORB keys appear in Type I, not Type II/III, and do not become CLASS
listing variables. Numeric missing keys and blank character keys are excluded via
the existing selection interface; raw input sort order is checked within each BY
group. MODEL NOINT is ignored with ABSORB as documented. Unsupported formatted
ABSORB keys, overlapping ABSORB/MODEL variables, uncorrected-total INT presentation,
confounded multi-effect Type III inference and default ABSORB graphs remain loud.
Initial or interactive LSMEANS requests with ABSORB are rejected, not silently lost.

A retained GLM session accepts subsequent RUN without replaying output, ignores
late ABSORB/BY/FREQ/WEIGHT/ID declarations, and ends on QUIT or a new DATA/PROC.
A repeated MODEL/CLASS after RUN is a captured user error. BY and unequal response
missing patterns disable interactivity; MANOVA's common missing pattern permits it.
Other interactive post-fit analyses remain explicit gaps. This does not claim a
new ESTIMATE/LSMEANS continuation implementation.

## Independent tests

- Two blocks, x=(0,1,2) in each and y=(1,2,2) plus a block shift of 10:
  absorbed rank 2, full rank 3, DFerror=3, slope=1/2, SSE=1/3, MSE=1/9,
  slope covariance=1/36. Compare against an independently augmented nuisance
  design fitted with QR. Weighted within-block sums vanish. Block SS=150,
  slope SS=1, F=9, and its p-value is independently `1/3-sqrt(3)/(2*pi)`.
- Separate WEIGHT and FREQ: effective precision weights (1,4,1) per block,
  frequency N=8, error DF=5, SSE=2/3, MSE=2/15, covariance=1/30. Multiplying
  precision weights by ten scales SSE/MSE but preserves coefficient covariance.
- Nested keys: four finest strata, full rank 5, error DF=3, SSE=1, slope=1,
  covariance=1/6, and absorbed DF increments (1,2).
- Missing keys/response, zero weights, source-row provenance, unsorted input,
  absorbed-only models, saturated fits, zero-DF confounded effects, and retained
  session/missing-pattern rules are covered with captured diagnostics.

The small exact-rational numeric tests use a dimension/operation-scale budget
`32*gamma(1024)*max(1,abs(reference))`, u=2^-53, for their bounded-condition
fixtures. The reference values are independently derived, not taken from actual
output or the seeded SAS listing. Six absorption tests and the main continuation
regression are imported by the normal gate.

## Both original results — not execution-only acceptance

`documented_feature.sas` remains exact: expected/actual status 0/0, all 671 listing
tokens match with whitespace normalization only, and three real native SVGs are
published. Only graph-publication notes appear in its stderr.

`targeted_statements.sas` now executes with status 0 and empty stderr, with all
108 fields/tokens present and correct observation/DF structure (40 observations,
model DF 4, error DF 35, total DF 39). **Its numerical oracle does not match.**
No numeric tolerance or expected-output alteration is used to call this a pass.

The discrepancy already exists before PROC GLM. A temporary diagnostic replay
kept the original seeded DATA step byte-for-byte and appended only MEANS/PRINT:

| Quantity | SAS original | OpenSAS generated input / fitted result |
|---|---:|---:|
| Input N | 40 | 40 |
| Input mean | 15.57985 | 15.584314333042066 |
| Input corrected total SS | 131.6028003 | 126.24475021099266 |
| Absorbed block SS | 60.79868964 | 41.92653117552084 |
| Adjusted group SS | 52.31226385 | 55.700395062517906 |
| Residual SS | 18.4918468 | 28.61782397295391 |
| MSE | 0.5283385 | 0.8176521135129688 |

An independent Fraction calculation on all forty round-trip printed OpenSAS
input values reproduces the OpenSAS absorption numbers: block means, group
contrast after block centering, residual SS and covariance DF. This separates
absorption correctness from seeded-input reproduction. The original does not
include raw SAS-generated rows, so the evidence does not identify the exact
random-stream algorithm discrepancy beyond the input-moment mismatch.
RAND/STREAMINIT was not changed, and generated data was not replaced with
fixture-specific values.

The task is therefore **PARK**, not DONE, unless the original seeded input can be
reproduced and the complete target output matched. The green implementation is
preserved for that dependency. All raw original results/diffs, the diagnostic
input program/output and the independent rational calculation are retained.
Final SHA/base, direct gate exit/counts, and both original statuses are reported
in the delivery message. No source/evidence from prior tickets was removed; no
board edits or pushes were made by dev2.
