# Bounded power/Pareto fallback diagnosis

This continues FEAT-univ-distributions after core 1f2b8b0. It does not introduce
another ticket or broaden the documented method contract. Two in-scope default
behavior mismatches remain; warning labels alone do not resolve either one.

## Scope: EPM is not part of this ticket

The full cited Sixth Edition text contains 22,444 lines. Running

    rg -ni '\bEPM\b|elemental.percentile|empirical.probability.method' /Users/thomas/kirha/opensas/docs/sas94-procedures-statistical.txt

returned no matches (exit 1). `manual-scope.txt` retains the path, hash and search
counts. M9's accepting EPM does not expand the cited contract. Its existing
unsupported_method result remains explicit, but EPM is no longer listed as an
acceptance gap and is not investigated further here.

## Mathematical constraints versus solver behavior

The cited formulas define beta/power positive shape and scale with data strictly
between theta and theta+sigma. Power is beta with its second shape equal to one.
For Pareto, sigma is positive and alpha can have either sign; alpha>1 is a valid
**distribution parameter**, not a syntax/domain error. Its upper endpoint when
alpha>0 is theta+sigma/alpha. Asymptotic MLE regularity (alpha<1/2) and the
manual's finite-local-MLE search region (alpha<=1) are not distribution-domain
restrictions. In particular, fixed-alpha>1 valid curves must not be rejected as
invalid parameters merely because estimating their endpoint is problematic.

For power, with y=x-theta, its log-likelihood is

    L = n log(alpha) - n alpha log(sigma) + (alpha-1) sum(log(y))
    dL/dsigma = -n alpha/sigma
    dL/dtheta = -(alpha-1) sum(1/y)
    dL/dalpha = n/alpha + sum(log(y)) - n log(sigma)

Thus estimated scale cannot have an interior stationary maximum. With fixed
theta its limiting boundary estimate is max(y). With alpha<1, moving theta
upward toward the smallest observation increases an unbounded likelihood.
That fact does not grant permission to substitute our boundary output for SAS's
finite returned curve, or to output a curve when SAS suppresses one.

For Pareto alpha>1, shrinking sigma toward alpha*max(y) makes the likelihood
unbounded. A finite returned alpha>1 curve is not a finite unconstrained MLE.
The profile root solver's no-root result is mathematically meaningful, but still
differs from SAS when SAS prints a finite feasible parameter table.

## Equivalent-family and heldout evidence

`likelihood-equivalence.sas` requests power and beta(beta=1) on six independent
sample/units combinations, with scale, both endpoints, or theta estimated.
All **18 paired requests** match in curve-presence/failure and in theta, sigma
and alpha at the retained ODS decimal precision. `equivalence-audit.json` is
produced and asserted by `analyze-diagnostics.py`.

The alpha=.5 sample has n=41, x=((i-.375)/41.25)^2. The second shape family has
n=101 and alpha=2. Scaling/translation heldouts include a factor ten, a factor
one tenth, and nonzero positive/negative offsets with corresponding fixed theta.
There is no fitted sample-specific switch. These equivalences indicate a shared
beta/power solver issue, not different likelihood definitions.

## Full-precision stopping and score evidence

`solver-diagnostics.sas` obtains ODS ParameterEstimates and records their HEX16
values. Its macro prints only existing data sets, so intentional no-curve cases
do not introduce PROC PRINT missing-data errors. Final runs:

- likelihood-equivalence: 0 errors, 40 warnings (20 fit failures and their
  20 absent-ODS-object warnings).
- solver-diagnostics: 0 errors, 18 warnings (eight fit warnings and ten
  absent-ODS-object warnings). Ten cases have no curve; two small-unit Pareto
  cases report only the no-estimates NOTE before the missing-ODS warning.

`analyze-diagnostics.py` decodes the exact IEEE values, reconstructs synthetic
samples independently of Zig, computes direct likelihoods/analytic scores, and
checks feasible likelihood improvements. It writes `score-audit.json`. The
script has no optimizer code or fitted-case constants.

For each of the three base power endpoint requests, MAXITER=1,2,20,1000 gives
**bit-identical** theta/sigma/alpha estimates. Increasing this option cannot fix
the mismatch on these cases. Returned scores are far from stationary:

| Request | SAS sigma | SAS alpha | Score in an estimated parameter |
|---|---:|---:|---:|
| theta=0, sigma=EST | .9716969696969697 | .5171650979229946 | dL/dsigma=-21.82138 |
| both endpoints EST | .9716969696969697 | .528649722075328 | dL/dtheta=1238.72886 |
| theta=EST, sigma=1, alpha=.5 | 1 | .5 | dL/dtheta=4611.38765 |

The scale-only shape score is about 4.77e-6, consistent with conditional shape
fitting, while its scale score is not near zero. The endpoint gaps are strictly
positive, so these are not optima attained on the documented support boundary.
The exact boundary solution improves scale-only log-likelihood from
12.42040091411566 to 12.45908766122506 (gain .03868674710940).

Translation by five preserves these normalized power results. Multiplication
by ten changes the scale-only request from a curve to failure. Scaling by .1
returns normalized sigma=.97421574461495 instead of .9716969696969697. Both
power and beta(beta=1) exhibit these changes. The base and factor-ten successful
scale values happen to equal sample range+.002; the factor-.1 result does not.
That observation is **not** sufficient evidence for hard-coding a .002 margin,
initialization, stopping rule, or parameter bound.

## Pareto nonregular fallback

For x=(1,2,3,4,6,8,10,15)+2, SAS returns the exact parameters

    sigma = 17.793117455502788
    alpha = 1.0451945031410557

The upper support gap is .02373807174672. Direct scores are
`dL/dalpha=39.54945335` and `dL/dsigma=-2.204994195`. Decreasing sigma by one
tenth of the current sigma-alpha*max(x) gap remains strictly feasible and
increases log-likelihood by .005702666107265. This directly refutes interpreting
that parameter table as a stationary optimum.

With fixed threshold transformed along with the data:

| Data transformation | SAS result, normalized back to original units |
|---|---|
| unchanged | sigma=17.7931174555, alpha=1.0451945031 |
| +5, theta=5 | identical |
| times 10 | sigma=17.7909042414, alpha=1.0450715370 |
| times .1 | no curve |

The scale-ten numerical differences are .0022132141 in normalized sigma and
.0001229661 in alpha. The factor-.1 **presence/absence mismatch** cannot be
explained by accepting a looser parameter tolerance. Shifts one and three
produce no curve under every tested unit/translation change.

## Code change and remaining acceptance

The only computation change is to make the numerical likelihood preserve the
exact identity B(alpha,1)=1/alpha, including the finite one-sided upper-boundary
value. Previously power admitted that finite likelihood while beta(beta=1)
returned -infinity. Explicit fixed-endpoint request validation remains strict.
This fixes a real helper inconsistency; it does not emulate SAS's optimizer.

Three new runnable regressions check power/beta likelihood identity, positive
Pareto/reflected-power equivalence with an independent analytic scale score,
and feasible improvements at the exact SAS-returned vectors. These tests explain
why the oracle vectors cannot be used as expected stationary roots; they do not
waive public-output equivalence.

Genuinely unresolved within the cited contract:

1. Reproducing shared beta/power finite stopping and sample/units-dependent
   curve suppression for estimated endpoints.
2. Reproducing Pareto's alpha>1 finite-return/failure selection. Current regular
   profile fitting still omits the shift-two curve that SAS returns.

No fitted constants, guessed default-margin rule, or wider warning-based
acceptance tolerance was added. Existing nonconverged candidates are diagnostic
numerical results, not evidence that mismatched default output is compatible.
