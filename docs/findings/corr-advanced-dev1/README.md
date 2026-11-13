# FEAT-corr-advanced — dev1 acceptance tracker

Status: **INCOMPLETE; do not mark DONE.** Assigned worktree/branch: opensas-dev1 / dev1.
Claim baseline a8de7cccf038af0dea74906838afb341f79f5d7c. Final rebased SHA and gate
counts are in the developer handoff, not asserted by this document.

## Implemented and checked against SAS 9.4 M9

- Spearman averaged ranks, pairwise missing deletion, compressed FREQ replication,
  Student t inference. Kendall tau-b with tie-corrected null variance and normal
  inference; N=2 p is missing. Rank methods reject WEIGHT.
- Pearson/Spearman/Kendall PARTIAL, complete-case deletion including controls,
  sequential symmetric Schur complements, SINGULAR= (default 1e-8), redundant
  controls excluded from residual degrees of freedom. Partial Kendall has no p.
  Overlapping analysis/control variables fail through captured diagnostics.
  Original CSSCP and partial CSSCP retained separately; partial variance uses
  n-k-1 or sum(weights)-k-1 only for DF/WDF, not N/WEIGHT.
- Fisher ALPHA, RHO0, BIASADJ YES/NO and LOWER/UPPER/TWOSIDED. Test statistic
  always adjusts the null bias; confidence estimate adjusts bias only when asked.
  Effective sample size subtracts the effective control rank. Perfect correlation,
  constants and insufficient residual N yield missing Fisher statistics.
- Raw and standardized Cronbach alpha and every deletion/item-total statistic;
  WITH is invalid; fewer than two variables suppresses alpha with a warning.
  Missing values are NOT silently listwise deleted: warn unless NOMISS. Standardized
  alpha uses the actual Pearson matrix, not covariance normalized by univariate
  variances, which would be wrong with pairwise missingness. Constants retain
  missing standardized alpha. Negative alpha and alpha above one are not clamped.
- Polyserial MLE with fixed marginal normal mean/scale, joint threshold/rho
  iterations, observed information including mean/scale nuisance parameters,
  Wald and LR inference; ORDINAL=VAR/WITH, NGROUPS=ALL/n, MAXITER, CONVERGE.
  Fully separated ordinal groups return boundary rho with missing SE/inference.
- Interior polychoric joint threshold/rho MLE through a CORR-owned specialization
  of the existing FREQ numerical kernel, with absolute parameter-change stopping. Tested balanced and strongly associated 3x3 tables and 2x2
  one-zero-cell boundary. Perfect ordered category bijection returns +/-1, SE=0,
  missing tests. NGROUPS and iteration failure return missing estimates with a
  visible warning. Sparse monotone boundary tables fail explicitly (see below).
- Hoeffding D coefficients including both kinds of ties, constants and FREQ.
  **Only HOEFFDING NOPROB is available.** A probability request fails explicitly.
- Separate typed Pearson/rank/ordinal results; NOPRINT/NOPROB/NOSIMPLE honored.
  Rank/ordinal simple statistics use frequency-weighted medians.

Reference: docs/sas94-procedures-statistical.txt printed pp10–18,21–32, read from
manager checkout because the ignored reference is absent from dev1. Existing
FEAT-corr-core findings and FREQ polychoric evidence were inspected before edits.
No shared FREQ file, jira.md, dispatch, or ODS infrastructure was modified.

## Blocking acceptance gaps (in scope, not exclusions)

1. **Hoeffding probability parity is not implemented.** A characteristic-function
   inversion of the theoretical BKR spectral distribution matched several rounded
   high-statistic listings but failed the discriminating low/medium grid below.
   More quadrature precision did not explain the difference. The unverified solver
   and its fixed upper-tail cutoff were removed from production; no approximate
   probability is silently exposed. `hoeffding-spectral-experiment.py` retains the
   standalone calculation, not an accepted implementation. Needed: reproduce and
   independently validate SAS's probability approximation across the distribution.
2. **Sparse monotone polychoric boundaries are unsupported.** For counts
   `[10,4,0;0,8,2;0,0,7]`, SAS gives rho=.99903, SE=.11695, Wald=72.9659,
   LR=40.9081. Reusing FREQ's kernel gave rho=.99930, SE=680551.59593 and p=1.
   CORR now rejects this identified shape through captured diagnostics. Needed:
   stable boundary likelihood/information treatment with SAS evidence. This is
   not marked outside scope. Manager should coordinate any shared FREQ repair.
The polychoric CONVERGE gap identified at the interim checkpoint is now closed:
`corr_polychoric.zig` specializes the existing Newton solver for absolute parameter
changes, without modifying FREQ. Bivariate-normal quadrature uses 1024 segments.
The asymmetric 3x3 N=1000 oracle exhausts MAXITER=3 and 4 at CONVERGE=.01;
with CONVERGE=1e-8 it gives rho=.94595, SE=.01381, LR=353.3860. Runnable
regression checks these cases (5e-6 coefficient/SE, 5e-5 LR). Source and stdout:
`converge-oracle.sas` / `converge-oracle.txt`.

Increasing quadrature resolution improved the sparse-boundary experiment to
rho=.99924814, SE=.38878795, but still did not match SAS .99903/.11695.
An analytic-derivative/Fisher-scoring experiment also failed that comparison;
it was not retained. The sparse-boundary guard remains, and the algorithm is
not claimed fully accepted.

Consequently no claim of full polychoric or Hoeffding inference completion is made.

## Oracle evidence and tolerances

Every probe used a unique absolute `/private/tmp/dev1-corr-*.sas` path and:

    /Users/thomas/sas/bin/sasrun /private/tmp/dev1-corr-NAME.sas -f text -o - -l /dev/null

`corpus-oracle.txt` retains the complete successful combined fixture run (zero
errors/warnings); the corresponding SAS source is retained. `boundpoly.txt`,
`alphaedge.txt`, and `hoeffding-grid.txt` retain stdout including the SAS run summary.
The other retained SAS sources reproduce the additional values reported here.
The alpha-edge oracle intentionally includes one invalid overlapping PARTIAL case.

Runnable regression in src/stat/corr.zig checks:

| Case | SAS reference | Absolute tolerance |
|---|---|---|
| Tied Spearman/Kendall x,y N=8 | .94612 / .83650; Kendall p=.0041 | 5e-6 coefficient; 5e-5 p |
| Partial Pearson/Spearman/Kendall controlling z | .93350 / .91539 / .61666 | 5e-6 |
| Partial Fisher lower limits | .556118 / .464915 | 5e-7 |
| FREQ Fisher LOWER, rho0=.5, alpha=.1, no bias adjustment | .903710 / .867847 | 5e-7 |
| Fisher UPPER rho0=-.5 | upper=.989857, p≈1 | 5e-7 limit |
| Raw/standardized alpha N=8 | .869050 / .976693 | 5e-7 |
| Missing weighted raw/standardized alpha | 1.002278 / .972118 | 5e-7 |
| Balanced 3x3 polychoric | rho=.59061, SE=.10494 | 5e-6 |
| Balanced 3x3 polyserial | rho=.51865, SE=.09703, LR=17.9375 | 5e-6; LR 5e-5 |
| Strong 3x3 polychoric/polyserial | rho=.93009/.82436, SE=.03050/.03886 | 5e-6 |
| 2x2 one-zero-cell polychoric | rho=-.999, SE=0, LR=17.2930 | 1e-10; LR 5e-5 |

The numerically differentiated Wald statistics are checked to 1e-3 absolute:
for the balanced table, current polychoric Wald=31.67254 versus SAS 31.6730,
and polyserial Wald=28.57034 versus SAS 28.5704. These are known last-digit
differences, not claims of four-decimal equality. Coefficients, SE and LR retain
the tighter tolerances in the table.

Hoeffding discriminating evidence (SAS precision from ODS printed with BEST32):

| Shape | N | D | SAS p | Experimental spectral p (rejected) |
|---|---:|---:|---:|---:|
| Untied scrambled permutation | 8 | 1/56 | .27035003097535 | .26958205804819 |
| Untied medium association | 8 | 9/28 | .00421936667347 | .00421210752780 |
| Untied scrambled permutation | 12 | 5/198 | .19028121558348 | .18976078064395 |
| Untied complete order | 20 | 1 | 0 | ≈4.4e-15 (cancellation-limited experiment) |
| Untied nearly ordered | 12 | 1 | 0 | ≈1.44e-9 |
| Tied x,y example | 8 | .388392857… | .0018 (listing) | .001827935… |
| Tied x,z example | 8 | .200892857… | .0197 (listing) | .019673681… |
| Compressed FREQ and explicitly expanded rows | 9 | -1/7 | 1 | not used |
| One constant margin | 6 | -.625 | 1 | not used |
| Both margins constant | 6 | -1.171875 | 1 | not used |

The low-statistic discrepancy is ~7.68e-4: it exceeds the 5e-5 tolerance needed
for agreement with a four-decimal probability listing. No relaxed tolerance was
used to declare it passing. D regressions use 1e-10 for exact rational cases and
5e-6 for five-decimal listings. FREQ and expanded D/rank results agree within
1e-10. Inference requests are tested as captured errors, not successful p-values.

## Corpus and integration

`tests/corpus/corr_advanced_dev1.sas` exercises supported listings. Its new `.txt`
is the compact interpreter layout, with numerical cells checked against the
retained SAS combined oracle; it is not a byte-for-byte SAS page-layout claim.
Expected-output addition is committed separately from implementation.

ODS handoff: `Group.pairs` remains Pearson only. `Group.spearman`, `kendall`,
`hoeffding`, `polychoric`, `polyserial`, `alpha`, and `unpartial_pairs` are separate.
The ODS producer must honor `spec.options.pearson` before publishing PearsonCorr
for rank/ordinal-only requests. Preserve dev5's capture hook when rebasing. No
advanced ODS publishing is claimed by this change.

Manager-owned grammar tracker needs a corresponding proc_corr update after
scope acceptance: SPEARMAN/KENDALL, PARTIAL, FISHER suboptions, ALPHA, SINGULAR,
POLYCHORIC/POLYSERIAL suboptions, and the explicit incomplete Hoeffding status.
This developer did not edit the shared EBNF or jira.md outside the owned slice.
