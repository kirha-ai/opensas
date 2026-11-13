# FEAT-univ-distributions — dev3 Johnson support

Status: SUPPORT implementation; parent ticket remains dev4's. This is not a
claim of full public-statement or exact SAS optimizer acceptance. No parser,
PROC, dev4 module, jira.md, or feature inventory was modified. The only shared
change is the permitted root.zig test import. Baseline: feat/stat/batch-3
9a4a503; bounce rebased once onto 6e35c58, preserving both Johnson and EDF
test imports. Read CLAUDE.md, lexer.zig, decisions.md (D-029), dev4's distribution
modules and retained findings before implementation.

## Contract for dev4

`src/stat/univ_johnson_fit.zig` exports:

- `fit(Family, Method, sorted_finite_sample, Fixed, Controls) Result`.
- `Family`: sb/su. `Method`: moments/mle; percentile fitting remains dev4's.
- `Parameters`: theta, lambda, delta, gamma. **lambda maps to SAS SIGMA**,
  not the inverse-Gaussian LAMBDA option. Z=gamma+delta*logit(y) for SB,
  Z=gamma+delta*asinh(y) for SU, y=(x-theta)/lambda.
- `Fixed`: nullable fields with those same names. Null means estimated, never
  a fixed starting value. The caller must apply family defaults: SB theta=0,
  lambda=1; SU all null. Passing all four fixed parameters validates support
  and returns them unchanged, including on constant samples.
- `Result.converged`: parameters, iteration/start counts, optional log-likelihood.
  Counts are zero for closed-form/fixed results. MOMENTS counts its successful
  Newton solve; MLE iterations count all starts. `Result.nonconverged` carries
  `{ reason, best: ?Success }`. Invalid requests and failed moment equations
  have no curve. MLE can retain the best finite, support-valid curve when its
  iteration budget expires or no interior maximum is established. The adapter
  must render that curve **with an explicit nonconvergence warning/status**;
  it must never relabel it converged or silently substitute percentiles. The
  optional payload contains actual parameters, log-likelihood and counts.
- `Controls`: optmaxiter=500, optmaxstarts=100, optboundrange=100,
  opttolerance=1e-8, positive optseed (deterministic helper default 1).
  Optional `trace(context, Iteration)` supplies start, iteration, parameters and
  log-likelihood for OPTPRINT delivery; the helper does not render or use ODS.
  Parser option applicability remains dev4's responsibility (OPT* is SU-only).

The helper owns no allocations, dataset access, grouping, FREQ expansion,
missing filtering, rendering or diagnostics reporter. Its input validation and
failure tags distinguish invalid samples/options, unsupported SAS parameter
combinations, support violations, no moment solution, iteration limit and no
interior likelihood maximum. Do not interpret every failure as invalid syntax.

## Manual and oracle evidence

Local manual: manager checkout `docs/sas94-procedures-statistical.txt`, printed
pp.326–327 (SB/SU options), 339 (OPT*), 401–402 (methods), 440–442 (formulas).
Both families support MOMENTS and MLE. The OPT* controls are documented for SU.
The extracted SU density's support line is inconsistent with its real-valued
asinh transformation; both dev4's module and actual SAS negative observations
confirm the unbounded SU convention used here.

All sources are invented deterministic data. Every oracle input/output/log is
under the unique absolute dev3 directory, never a shared /tmp/foo.sas. Commands:

    /Users/thomas/sas/bin/sasrun /Users/thomas/kirha/opensas-dev3/docs/findings/univ-johnson-dev3/methods.sas -f text -o - -l /dev/null

The text from that command is retained as methods.txt. Subsequent probes use
explicit absolute sibling .txt/.log paths to retain warnings and optimizer
statuses. SAS 9.4 M9 outputs, not our helper, are the expected-value source.
The .txt/.log evidence is committed separately from code and test fixtures.

- `methods`: n=101 normal scores transformed into SB and SU. MOMENTS uses the
  corrected sample variance, skewness and excess kurtosis, not population
  denominators. SB first estimates all four parameters, then replaces specified
  endpoints without recomputing shapes. SU fixed-endpoint MLE and SB MLE use
  transformed-normal variance with divisor n, giving delta=1.219036.
- `constraints` and `combos`: SAS rejects SB MLE with either endpoint estimated,
  SB partially fixed shapes, SB estimated theta with fixed scale, and SB fixed
  shapes with an estimated endpoint. SB MOMENTS permits all parameters estimated,
  both endpoints fixed, or theta fixed with scale estimated. SU MOMENTS requires
  all parameters estimated (all-fixed curves need no fit).
- `heldout`: independent n=77, opposite skew, changed shifts/scales/shapes.
  SB MOMENTS and MLE, SU MLE with free endpoints, each endpoint held fixed and
  gamma held fixed. SAS itself reports "Unable to solve moments equations" for
  this SU sample; the helper also returns no_moment_solution.
- `boundaries`: n=51 symmetric SB/SU, normal scores, strict tolerance, one-start
  controls, one-iteration OPTPRINT, and observations at SB endpoints. The final
  endpoint error is intentional oracle evidence, not a clean successful run.
- `su-fixed-shapes`: SU endpoint optimization with delta, gamma, or both held
  fixed. This verifies conditional fitting never overwrites supplied shapes.
- `fallback-status`: one-iteration SU fits with fixed location or gamma retain
  curves and the fixed values while OPTPRINT reports IterLimit. This establishes
  that diagnostic status must not erase otherwise valid numerical output.

## Numerical method and precision

MOMENTS solves skewness/kurtosis equations with damped two-variable Newton and
multiple initial shape values. SU uses analytic normal-exponential central
moments; an independent quadrature test checks those formulas. SB uses central
normal-transform Simpson integration and verifies refinement agreement before
returning a fit. Mean/variance determine scale and location; fixed SB endpoints
are replaced only after that solve, matching SAS.

MLE profiles free gamma/delta analytically, including SU with either shape
fixed. Free endpoints use scaled location/log-scale coordinates, numerical
profile derivatives, damped Newton descent, and seeded multiple starts. Positive
curvature and a gradient criterion are required; a finite boundary iterate is
not an interior maximum. The first start is the standard percentile estimate
when available; otherwise mean/standard deviation supply a finite start.
OPTBOUNDRANGE controls the subsequent range (relative to the initial scale for
location, log(1+range) for scale). OPTMAXITER caps each local solve and
OPTMAXSTARTS caps starts. Trace callbacks also include unsuccessful starts.

Normal-score CSV test inputs are generated independently with Python's
statistics.NormalDist inverse CDF, matching SAS PROBIT inputs to floating-point
precision. They contain input values, not fitted expected output. The retained
`generate-scores.py` reproduces them.

Oracle checks use displayed-precision tolerances: 6e-7 for closed-form shapes,
6e-6 for most moments, 2e-5/3e-5 for SU optimization. Heldout SB MOMENTS permits
5e-5 because SAS's fitted variance differs from the sample target by about
1.06e-5 using the displayed parameters (target 1.2468352864645125, SAS fit
1.2468458469891612). Our moment solve enforces the equations more closely;
this is numerical stopping/quadrature agreement, not bit-for-bit emulation.

## Acceptance limits that the adapter must preserve

SAS's proprietary active-set multistart trajectory, sample-point generator and
random sequence are not replicated. Seeds repeat this helper's computation,
not SAS's individual starts. OPTPRINT receives this solver's real trace, not a
fabricated SAS iteration history. Equivalent finite interior fits are checked
against the independent probes; exact optimizer trajectory parity is unverified.

SAS can print approximate fallback curves even with no established optimum:
`boundaries.log` explicitly records IterLimit, zero distinct local optima, and a
returned sample-point solution after OPTMAXITER=1. Normal-score SU MLE prints
scale=101.3848, delta=104.3006 near the normal limit. The original core dropped
these curves; that was a concrete compatibility gap, not an acceptance exclusion.
The incremental fallback change now returns the best valid curve in
`nonconverged.best`, retaining the reason and never asserting an optimum. Invalid
trial points, unsupported requests and support failures do not gain a fallback.
The final accepted step is considered even if it exhausted the iteration budget.
A better stopped candidate is not hidden by a worse converged local optimum.

The regression checks both one-iteration and normal-limit payloads, finite direct
observation-wise log-likelihood, exact fixed-parameter preservation, support and
iteration counts. The one-iteration curve's likelihood is at least the likelihood
of SAS's retained printed fallback vector (allowing its displayed rounding),
without requiring the same parameter vector from different local solvers. Nine
standalone tests now cover the helper. The core bounce alone passed 1266 tests,
2052 corpus fixtures and 11 programs at be9af09; the incremental fallback change
requires its own full gate before landing.

Remaining numerical difference: own seeded starts and optimizer trajectories
can produce different finite fallback parameters and different local stopping
statuses from SAS, especially near the normal/lognormal limits. We report the
actual unresolved status and actual curve, not a fabricated SAS vector or trace.
Converged interior fits remain checked against the retained M9 heldouts. Exact
random-start trajectory parity is not claimed or required by this support task.

The parent still needs the adapter, parser option checks, captured error mapping,
OPTPRINT/ODS delivery and public regression acceptance. No helper-only green run
can mark the parent ticket done. Final rebase/gate SHA and exact suite counts
are reported to the manager rather than inferred here.
