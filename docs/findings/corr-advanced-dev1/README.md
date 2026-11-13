# FEAT-corr-advanced — dev1 acceptance tracker

Status: **INCOMPLETE; do not mark DONE.**

Latest bounded follow-up: [quadrature-descent/README.md](quadrature-descent/README.md)
fixes a false likelihood/convergence signal in case 2 and adds independent
finite-SE controls. The diagnostic candidate improves to 37/40, retaining all
35 prior passes; cases 3, 21 and 22 remain. No tight-boundary guard was removed.

Sparse-boundary update: default/loose inference now passes SAS original, mirrored,
transposed, relabeled and held-out cases. See [sparse-boundary.md](sparse-boundary.md).
Only unresolved tight-tolerance boundary information remains explicitly rejected.
The older failure numbers below are retained as historical evidence. Assigned worktree/branch: opensas-dev1 / dev1.
Hoeffding probability integration is now accepted; see [hoeffding-integration.md](hoeffding-integration.md).
The remaining polychoric investigation is in [singular-information.md](singular-information.md).
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
- Polychoric joint threshold/rho MLE with positive rectangle integration, analytic
  cell derivatives, Pearson initialization and Fisher scoring with absolute stopping. Tested balanced and strongly associated 3x3 tables and 2x2
  one-zero-cell boundary. Perfect ordered category bijection returns +/-1, SE=0,
  missing tests. NGROUPS and iteration failure return missing estimates with a
  visible warning. Unresolved tight-tolerance boundary information fails explicitly (see below).
- Hoeffding D coefficients including both kinds of ties, constants and FREQ.
  HOEFFDING probabilities now use the landed SAS-calibrated support module.
  Small-N missing inference and NOPROB suppression are covered by public tests.
- Separate typed Pearson/rank/ordinal results; NOPRINT/NOPROB/NOSIMPLE honored.
  Rank/ordinal simple statistics use frequency-weighted medians.

Reference: docs/sas94-procedures-statistical.txt printed pp10–18,21–32, read from
manager checkout because the ignored reference is absent from dev1. Existing
FEAT-corr-core findings and FREQ polychoric evidence were inspected before edits.
No shared FREQ file, jira.md, dispatch, or ODS infrastructure was modified.

## Acceptance gaps and resolutions (no scope exclusions)

1. **Hoeffding probability gap closed.** Dev5's independently verified calibrated
   distribution is integrated through `probability(D,N)`. The prior spectral
   experiment below remains historical evidence, not production. Public CORR
   tests cover the discriminators, tied/FREQ data, missing pairs, N=4/5/6, NOPROB
   and ODS advanced capture rejection. See `hoeffding-integration.md`.
2. **Tight-tolerance polychoric boundary information remains unresolved.**
   The original blanket sparse failure below is now fixed for default/loose settings;
   [sparse-boundary.md](sparse-boundary.md) records accepted cases and the narrower gap. For counts
   `[10,4,0;0,8,2;0,0,7]`, SAS gives rho=.99903, SE=.11695, Wald=72.9659,
   LR=40.9081. Reusing FREQ's kernel gave rho=.99930, SE=680551.59593 and p=1.
   The first WIP rejected this shape. The current solver handles it at default/loose
   tolerances and rejects only unresolved information at tighter settings. Needed:
   stable boundary likelihood/information treatment with SAS evidence. This is
   not marked outside scope. Manager should coordinate any shared FREQ repair.
The stopping norm is now pinned by explicit SAS MAXITER/CONVERGE discriminators
in `quadrature-descent/`. CORR uses relative parameter change with an absolute
fallback near zero, matching the actual reference and existing FREQ convention.
The earlier absolute-only interpretation was insufficient. FREQ is unchanged.
The asymmetric N=1000 checks remain, and new independent finite-SE controls pass.

Increasing quadrature resolution improved the sparse-boundary experiment to
rho=.99924814, SE=.38878795, but still did not match SAS .99903/.11695.
An analytic-derivative/Fisher-scoring experiment also failed that comparison;
it was not retained. Those were intermediate experiments. The later scoring/initialization fix is in
[sparse-boundary.md](sparse-boundary.md); full tight-boundary acceptance remains open.

Full polychoric acceptance is still open; Hoeffding probability integration is accepted.

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
for the balanced table, the old polychoric Wald was 31.67254 versus SAS 31.6730; the current scoring
solver gives 31.67302,
and polyserial Wald=28.57035 versus SAS 28.5704. These are known last-digit
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
1e-10. The former probability rejection is removed. Integrated inference is now checked
at 5e-13 absolute against full-precision SAS p-values; invalid combinations and
advanced ODS mislabeling remain captured errors.

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

The authorized CORR grammar section now annotates: SPEARMAN/KENDALL, PARTIAL, FISHER suboptions, ALPHA, SINGULAR,
POLYCHORIC/POLYSERIAL suboptions, and the remaining tight-polychoric guard.
No other EBNF sections or jira.md were edited.
