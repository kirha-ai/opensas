# FEAT-univ-distributions acceptance inventory

Status: IN PROGRESS; not accepted or complete.

Baseline: local feat/stat/batch-3 a8de7cc. The baseline has summary and
inference modules, but rejects all five plot statements before computation.
Read CLAUDE.md, lexer.zig, decisions.md (including D-029), the retained
univ-summary/README.md and univ-normality.md before implementation.
The ignored manual and retained evidence are read from the manager checkout.

## Required numerical surface

Source: SAS 9.4 Statistical Procedures pp.307–341, 359–407, 431–459;
output descriptors additionally pp.462–463. Only graphics rendering is outside
this ticket; numerical rendering and public statement behavior belong to dev4.

- Thirteen families: beta, exponential, gamma, Gumbel (maximum extreme
  value), inverse Gaussian, lognormal, normal, generalized Pareto, power,
  Rayleigh, Johnson SB, Johnson SU, Weibull.
- Fixed and estimated parameters, per-family defaults, aliases, parameter
  lists matched by position, threshold/scale support constraints.
- Gamma ALPHAINITIAL/ALPHADELTA/MAXITER, Weibull MAXITER/ITPRINT,
  Johnson percentile/moments/MLE methods and FITINTERVAL/FITTOLERANCE;
  SU optimizer controls and convergence reporting.
- EDF D, A2, W2 statistics and parameter-dependent availability (Table 4.31).
  Tabulated/interpolated probabilities for seven families; simulated
  probabilities and EDFSEED/EDFNSAMPLES for Gumbel/IGAUSS/Pareto/Rayleigh.
- Normal/quadratic/triangular kernels; C numeric/MISE/SJPI, lists with
  last-value repetition, LOWER/UPPER reflection and bounded support.
- HISTOGRAM fitted-bin probabilities, observed counts/percentages,
  MIDPERCENTS/PERCENTS, NOPRINT; endpoints/midpoints, RTINCLUDE,
  VSCALE and OUTKERNEL/OUTHISTOGRAM numerical values and descriptors.
- CDF and PP values; QQ/probability standard quantiles, mandatory shape
  options, Blom ranks/RANKADJ/NADJ, Weibull2 logarithmic transformation,
  fitted reference intercept/slope and percentile calculations.
- BY/CLASS/VAR, missing/FREQ/WEIGHT behavior, empty/constant samples,
  invalid parameter and unsupported request diagnostics.

## Integration contract

Computation must accept sorted finite samples after grouping and FREQ handling,
return typed numerical results, and never render or perform ODS registration.
Dev4 owns statement dispatch in runUnivariate, per-group delivery to the landed
ODS infrastructure, numerical rendering and output datasets. Manager coordinates
landing and does not implement feature code. Blanket plot guards must not be silently removed without
preserving diagnostics for unsupported graphics requests.

## Implementation checkpoint (not ticket acceptance)

- `univ_distributions.zig`: all thirteen fixed-family densities, CDFs, inverse
  CDFs, parameter validation, raw D/W2/A2 statistics and rank probabilities.
  Inverse-CDF round trips cover all families; these are numerical checks, not
  a claim of full SAS acceptance for all fixed-parameter combinations.
- `univ_distribution_fit.zig`: closed-form normal/lognormal/exponential/
  inverse Gaussian/Rayleigh/power estimates; gamma/Weibull iterations;
  beta shape Newton iterations; Gumbel scale score;
  Johnson SB/SU percentile fits. Estimated gamma/lognormal/Weibull thresholds
  search for an interior profile maximum, never accept a boundary iterate.
- `univ_distribution_parse.zig`: family parameter lists, EST, parameter
  aliases, gamma/Weibull iteration controls, Johnson percentile controls,
  PERCENTS, MIDPERCENTS and NOPRINT. Unknown options fail via captured diagnostics.
- `univ_distribution_gof.zig`: complete-parameter and fitted-normal EDF tables,
  finite-sample corrections and stored p-value bound signs. Other estimated-
  parameter and simulation methods remain guarded.
- `univ_kernel.zig`: three kernels, reflections, numeric and normal-reference
  MISE bandwidths; direct density and SAS's 128-interval binned/interpolated
  density are separate APIs. SJPI is explicitly unsupported.
- `univ_distribution_values.zig`: explicit equal-width endpoint counts,
  RTINCLUDE, observed and fitted percentages, occupied-outer-bin trimming,
  standardized QQ/probability coordinates/reference lines, Weibull2 transform.
- Public HISTOGRAM dispatch, explicit/automatic bin calculation, BY/FREQ,
  OUTHISTOGRAM and OUTKERNEL are implemented in the current working tree.
  Numerical tables publish typed ParameterEstimates/FitQuantiles/GoodnessOfFit/
  Bins objects using the landed ODS builder. Existing summary ODS hooks remain.
  Integration tests check output values, descriptors and absence of unrequested
  output datasets. Constant/comparative bins and broader metadata remain open.
- SAS M9 rejects WEIGHT with all five plot statements. The public guard is a
  compatibility error (not a feature-gap exemption), before output publication.
- Singer owns new standalone SJPI support. Dev4 retains its adapter, all existing
  modules, statement behavior, numerical rendering and final acceptance.

### Oracle findings

Retained source/output/log triplets have unique `dev4-univ-...` names. Commands:

    /Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o - -l /dev/null

Retained reruns use explicit absolute output/log paths. NOPLOT avoids a server
graphics-directory permission error in the initial probes. The retained NOPLOT
families contain no SAS ERRORs. The n=8 gamma warning and the thresholds-family
Pareto failure are real SAS outcomes, not waived acceptance failures.

1. `distributions` and `fixed`: normal fixed MU uses the conditional divisor n;
   lognormal fixed ZETA still uses n-1. Exponential with both parameters estimated
   uses bias-corrected theta=(n*min-mean)/(n-1), sigma=mean-theta. If sigma is fixed,
   estimated theta is the sample minimum. Gumbel uses the maximum-extreme-value
   convention, despite the ambiguous/sign-inconsistent extracted manual text.
2. `beta`: beta/power fits and Gumbel fixed/estimated location. Gumbel scalar
   score roots differ from SAS's stopped optimizer by up to about 5e-6 on this
   sample; tests state this tolerance instead of claiming last-bit agreement.
3. `johnson`: four default empirical percentiles reproduce SB/SU shape estimates.
   Fixed SB endpoints replace percentile estimates without refitting shapes.
4. `thresholds`: SAS lognormal uses the adjusted n-1 profile, returning
   theta=.896031; the unadjusted likelihood gives .398939 and is incorrect here.
   Gamma/Weibull optimizer comparisons use explicit 5e-5/2e-5 parameter tolerances.
5. `kernel` and `kernel-check`: normal-reference pilot scale is IQR/1.34898;
   standardized bandwidths .78520352, 1.738287, 1.9096135 remain the same for
   a second sample containing extreme outliers. OUTKERNEL uses linearly binned
   observations and interpolated grid values. Bounded reflection interpolates
   the reflected grid and zeroes outside-support ordinates before interpolation.
6. `pareto-convergence`: shifted versions of the n=8 sample show SAS failure at
   shift=1 and shifts>=3, but a boundary estimate alpha=1.045195 at shift=2.
   A mathematical interior-profile solver does not reproduce this optimizer
   behavior. Estimated Pareto requests therefore still fail explicitly; fixed
   Pareto probabilities/densities/quantiles remain available in the helper.
7. `sjpi`: SAS returns standardized bandwidth .7148286478 on the n=8 sample
   and changes nonnormal requested kernels to normal with a warning. This is
   not reproduced by the tested standard direct-plugin/solve-equation pilot
   formulas. The SJPI request guard remains until its SAS variant is established.
8. `edf-known`: 369 EDF rows over n=20/100/500 and 41 shape perturbations.
   Complete-parameter table interpolation reproduces every stored probability
   to max absolute error 7.511e-14, with zero bound-sign mismatches. Independent
   fixed beta(2,3) probe agrees at displayed precision. Unit checks cover all
   three sample sizes and both probability bounds.

### Remaining acceptance gaps

The ticket is NOT DONE. Remaining work includes:

- Johnson MOMENTS/MLE and optimizer controls; beta/power endpoint/scale
  estimation; Pareto estimation and boundary convergence cases.
- EDF availability rules, estimated-parameter probability tables/interpolation
  and simulation controls. Complete-parameter probabilities are implemented.
- SJPI; complete automatic output grids and OUTKERNEL/OUTHISTOGRAM descriptors,
  default bins, numeric range grammar and complete option-list semantics.
- Full plot-statement parsing/PROC dispatch, table rendering and landed ODS
  delivery; BY/CLASS/FREQ/WEIGHT and empty/degenerate end-to-end acceptance.
- Broader independent SAS verification of all distributions, parameter
  combinations, tails, rank options and numerical convergence boundaries.

New unit checks are directly runnable via `zig build test`. The working-tree
`univ_dist_hist_dev4` corpus fixture has a SAS-derived golden; implementation and
golden will be committed separately. Full gate status is recorded at report-time,
not inferred from unit tests. No jira.md edit, fetch, pull or push.

The earlier green foundation report rebased once at report-time onto 0f2d151 and
recorded HEAD 0196bb1: 1237 tests, 2050 corpus, 11 programs. The current integration
work is newer and does not inherit that gate result.

## Dependency integration checkpoint

Manager explicitly authorized acquiring the landed support before full ticket
completion. Current public WIP and its separate SAS golden were committed, then
rebased onto 5297a4b without conflicts or discarded work. The final checkpoint
rebase/gate is recorded in the manager report and opensas-last-green.

Adapters now call `univ_johnson_fit`, `univ_endpoint_fit`, and
`univ_edf_inference`. Johnson MOMENTS/MLE options and real OPTPRINT trace data
reach public HISTOGRAM execution. A finite nonconverged Johnson fallback keeps
its warning and status; no-fit results produce blank fitted-curve output rather
than being relabelled converged. Beta estimated endpoints and regular Pareto
fits use the landed helper's private numerical controls, not PROC MAXITER.
Uniform Pareto's upper endpoint has finite density; the power/beta(alpha,1)
closed-upper-boundary representation is available for eventual accepted fits.

EDF results carry nullable probabilities. SAS-unavailable tests do not create
rows or an empty ODS object. The wrapper handles supported partial normal,
lognormal and Weibull cases. Four simulation families use inverse-CDF sample
generation and actual constrained refitting, with one resolved seed and the
requested replication count. Failed or nonconverged refits propagate without
retry, discard, or renormalization. Independent Monte Carlo checks use the
retained dev5 M9 evidence: four fixed families and estimated-scale Rayleigh,
2000 new replications versus 10000 SAS replications, with pooled binomial
uncertainty. Estimated Gumbel/IGAUSS/Pareto callbacks still need broader M9
acceptance. Seed repetition and failure propagation are directly tested.

Targeted integration run before the final gate: 58/58 UNIVARIATE tests. Public
checks cover Johnson methods, fixed constraints, a warned one-iteration fallback,
OPTPRINT, typed ODS parameters, beta endpoint adaptation, histogram BY/FREQ,
OUTKERNEL grid values/descriptors and no unrequested output dataset publication.
The `univ_dist_hist_dev4` golden comes from the actual source/output/log triplet
at `/private/tmp/dev4-univ-hist-integration-20261113.*`; its `.sas` source is
also committed as the runnable corpus fixture. The golden is a separate commit.
The final checkpoint fixture combines both output datasets in one FILE PRINT
step to avoid testing DATA-step page separation. Its fresh M9 rerun is retained
at `/private/tmp/dev4-univ-hist-checkpoint-v2-20261113.*` and reports zero errors
and warnings. All 18 numerical rows are unchanged; the separator disappears.

Precise remaining tags (none waived by a green checkpoint):

- **PUBLIC-PLOTS:** CDFPLOT/PPPLOT/QQPLOT/PROBPLOT public dispatch remains guarded;
  numerical point/quantile helpers exist, but public execution is unfinished.
- **BINS-OUTPUT:** constant/comparative bins, KEY/UNIFORM/count controls, automatic
  kernel grid extent, range/list completeness and full BY/CLASS metadata/output
  option ordering need completion. Selected explicit and automatic cases pass.
- **EDF-TABLES:** exponential/gamma/beta/power and estimated-threshold tables
  remain under support work; available but missing tables still fail loudly.
- **SJPI:** Singer's standalone algorithm is not yet available for integration.
- **ENDPOINT-FALLBACK:** power estimation and nonregular Pareto/beta stopping and
  finite fallback parity remain unresolved by the support helper. Power's
  unsupported endpoint-estimation guard remains; no warning is treated as proof
  that a mismatched SAS curve is accepted.
- **PARETO-PRESENCE:** the retained 51-point gamma-score sample yields a finite
  profile fit (theta=0, sigma about12.1890493, alpha about.6524813) while M9's
  `dev4-univ-thresholds` probe suppresses the Pareto curve. The old guard-based
  expect-error assertion is not used to falsely reject the now-implemented
  regular solver. This concrete curve-presence discrepancy remains unaccepted.
- **TRACE/PARITY:** Weibull ITPRINT remains explicit; Johnson real traces/status
  are delivered, but proprietary SAS optimizer trajectories are not replicated.
- **FINAL-ACCEPTANCE:** full public heldouts, remaining option/schema behavior,
  and full ticket validation are not complete. No jira.md change or completion
  claim is made by this checkpoint.
