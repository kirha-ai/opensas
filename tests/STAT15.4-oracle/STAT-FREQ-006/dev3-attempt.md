# STAT-FREQ-006 — independent association verification

Result: existing implementation verified; evidence-only completion. No production, regression,
expected golden, shared main/proc, board or skill changes. Starting base after fast-forward:
`a30993a94ef924c26429dcde8ef97f810932c8c5`; branch `codex/stat-dev3`.
Read the full ticket, own README, all listed SAS/expected/status/log files, and manual physical
pages 3170–3180. Final SHA/base and direct-exit `gate -j2` counts are in the handoff.

## Reproduce without duplicating listings

```sh
python3 tests/STAT15.4-oracle/STAT-FREQ-006/verify.py --output /absolute/fresh/output-directory
```

The replay retains complete actual stdout, stderr, return statuses, SVGs, and a manifest.
`dev3-verification.json` records input/expected/output hashes, every observed diagnostic,
independent numerical references and graphic hashes. Informational SVG-note paths depend on
output directory. No diagnostic is removed. Only listing whitespace runs/edges are normalized;
there is no numerical tolerance or field/table filtering in the full listing comparisons.

## Original oracle

The ticket's own unchanged `documented_feature.sas` was independently executed: **649/649 tokens
match**, status **0**, no actual/reference warnings or errors. All tables, numeric fields,
headings and rules participate. Actual informational diagnostics are three SVG-written notes;
SAS source echoes, workspace/read and page notes differ, and are not claimed exempt.
Current OpenSAS runtime identity is retained; no SAS version string is substituted.

The supplied case does not request MEASURES; it is not sufficient alone to validate this ticket.
Therefore the existing `freq_tests_association.sas` (MEASURES(CL), TEST MEASURES, PLCORR) and
`freq_tests_edges.sas` were also independently executed unchanged. Their complete listings
match their existing goldens and both return 0. Existing gate coverage is reused, not duplicated.

## Independent estimates, SEs, confidence limits and tests

For the nine-cell sample [[12,5,3],[4,17,6],[2,8,13]], N=70, row totals=[20,27,23] and
column totals=[18,30,22]. Direct ordered-pair counting gives P=1856 and Q=434. Thus Gamma
is 1422/2290; row/column tie denominators are 3242 and 3192. Somers C|R=1422/3242 and
R|C=1422/3192; tau-c=2133/4900. Lambda C|R=12/40, R|C=15/43, symmetric=27/83.
These distinguish directions, tie corrections, and symmetric versus asymmetric definitions.

The standalone verifier evaluates the manual's estimator expressions using 60-digit Decimal
forward derivatives. Multinomial count covariance is diag(n_i)-n_i*n_j/N. Applying the delta
method gives the ASEs independently of OpenSAS's variance routines. Rank-score derivatives
are included for Spearman; unique maxima make the lambda derivatives unambiguous. Entropy
expressions give the three uncertainty coefficients. Confidence intervals use estimate ±
normal(0.975)*ASE. Seven ordinal/correlation null variances use the numerator derivative
at the zero-null hypothesis; normal tails are computed independently with erfc.

All **13 estimate/ASE/lower-CI/upper-CI rows** match exactly at four displayed decimals, and
all **seven null-SE/Z/one-sided/two-sided fields** match. Unrounded reference values remain in
the manifest; no blanket tolerance masks differences. DF is not applicable to these normal Z
tests. Gamma's ASE=0.1234 differs from its null SE=0.1433; its Z=4.3327 correctly uses the
latter. The five concordance tests share Z=4.3327, while Pearson and Spearman give 4.0008 and
4.4188. All displayed p-values are <.0001, matching independent tails.

The complete supplemental golden also checks polychoric estimates, SEs, CIs, Wald and likelihood
ratio output. Existing unit coverage pins simultaneous-threshold polychoric MLE, its ASE,
convergence behavior and boundary behavior; no new inference algorithm was duplicated.

## Boundary and diagnostic checks

The existing edge case retains a zero row [[0,0],[3,5],[4,1]] with WEIGHT/ZEROS and requests
CHISQ/MEASURES/PLCORR. It returns status 0, displays `Row or column sum zero. No statistics
computed for this table.`, and emits no association estimates in that final stratum (N=13).
This follows the documented zero-margin restriction (also stated on physical page 3158).
The full edge fixture includes tied modes, fractional counts and forced polychoric nonconvergence.
Its complete diagnostics are retained in the manifest: noninteger Fisher omission and polychoric
nonconvergence are NOTE messages, not errors. Existing captured-diagnostic and zero-variance
unit tests assert missing tests rather than invented estimates when quantities are undefined.

## Graphics

All three fresh oracle SVGs were rendered and visually inspected: clustered frequency plots
for boys and girls plus the agreement plot. Bar counts [27,29,14,35] and [23,10,53,32] are
also checked from SVG data attributes. Category order, legends and axes are correct; agreement
uses ordered ratings and cumulative scale to N=88. No clipping/overlap observed. Styling differs
from SAS and pixel parity is not claimed. SVG hashes make the inspected results reproducible.
