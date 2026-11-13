# FEAT-univ-distributions acceptance inventory

Status: IN PROGRESS; not accepted or complete.

Baseline: local feat/stat/batch-3 a8de7cc. The baseline has summary and
inference modules, but rejects all five plot statements before computation.
Read CLAUDE.md, lexer.zig, decisions.md (including D-029), the retained
univ-summary/README.md and univ-normality.md before implementation.
The ignored manual and retained evidence are read from the manager checkout.

## Required numerical surface

Source: SAS 9.4 Statistical Procedures pp.307–341, 359–407, 431–459;
output descriptors additionally pp.462–463. Rendering is outside this ticket.

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
Manager/dev5 integration needs statement dispatch in runUnivariate and per-group
delivery to ODS. Blanket plot guards must not be silently removed without
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
- `univ_kernel.zig`: three kernels, reflections, numeric and normal-reference
  MISE bandwidths; direct density and SAS's 128-interval binned/interpolated
  density are separate APIs. SJPI is explicitly unsupported.
- `univ_distribution_values.zig`: explicit equal-width endpoint counts,
  RTINCLUDE, observed and fitted percentages, occupied-outer-bin trimming,
  standardized QQ/probability coordinates/reference lines, Weibull2 transform.
- `univariate.zig` imports these modules in its test block. No PROC dispatch
  guard is removed and no ODS infrastructure is modified. These APIs are not
  yet reachable through a completed end-to-end PROC implementation.

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

### Remaining acceptance gaps

The ticket is NOT DONE. Remaining work includes:

- Johnson MOMENTS/MLE and optimizer controls; beta/power endpoint/scale
  estimation; Pareto estimation and boundary convergence cases.
- EDF availability rules, all probability tables/interpolation and simulation
  controls. Raw statistics are not a substitute for those probabilities.
- SJPI; complete automatic output grids and OUTKERNEL/OUTHISTOGRAM descriptors,
  default bins, numeric range grammar and complete option-list semantics.
- Full plot-statement parsing/PROC dispatch, table rendering and dev5 ODS
  delivery; BY/CLASS/FREQ/WEIGHT and empty/degenerate end-to-end acceptance.
- Broader independent SAS verification of all distributions, parameter
  combinations, tails, rank options and numerical convergence boundaries.

No expected-output golden is changed. The new tests are directly runnable via
`zig build test`; full gate status must be recorded at landing, not inferred
from these unit tests. No jira.md edit, fetch, pull, push, or mid-task rebase.
