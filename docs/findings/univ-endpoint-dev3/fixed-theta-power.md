# Fixed-theta power scale compatibility path

Implemented in `src/stat/univ_endpoint_fit.zig` after prospective validation.
This closes the defined admissible fixed-theta power scale path, not all power,
beta or Pareto compatibility. One inadmissible-moment/free-alpha fallback is
retained explicitly as a mismatch. Parent FEAT-univ-distributions is not done.

## Frozen validation and bounded follow-ups

`generate-prospective-power.py` generated 34 fresh requests before their results
were inspected: n=29 beta(.6,1.4), n=59 power(.35), n=83 power(1.4), n=19
beta(2,5); fixed alpha=.4/2 and estimated alpha; translations and scales; small,
constant, symmetric heavy-tail and tied samples. Invalid-moment requests use a
fixed theta just below the minimum, so the simple range+.002 fallback is feasible
and failure is not confused with an inadmissible fixed support. Twelve requests
also test free-location and joint-endpoint behavior.

`initialization-edges.sas` adds ten targeted cases to distinguish invalid
four-moment geometry, conditional shape admissibility and supplied alpha. It
includes unequal/two-level samples and another symmetric heavy-tail sample.
All oracle source, result and log paths are unique absolute dev3 paths. The
prospective run has 0 errors/22 warnings; the edge run has 0 errors/8 warnings.
Warnings include missing ODS objects for intentionally failed requests.

Both sources retain exact observations and ODS estimates as HEX16. The independent
Python analysis keeps the original frozen-rule predictions as well as the
implementation policy; the initial counterexamples are not overwritten or hidden.
`export-power-regression.py` also exports the previous 53 power requests plus
32 new fixed-theta cases to the uniquely owned runnable regression fixture.

## Implemented computation and API status

When theta and sigma are supplied, the existing closed-form conditional alpha
MLE remains available and needs no four-moment pilot. This includes samples
smaller than four when otherwise valid.

When theta is supplied and sigma is estimated:

1. Compute corrected variance, skewness and excess kurtosis using observations
   normalized by their range. This avoids overflow and cancellation from large
   translations. Derive the four-moment beta width when its shape geometry is
   admissible, using the previously validated formula.
2. Set sigma to range+min(.002,.1*(moment_width-range)). If the four-moment shape
   geometry is inadmissible but alpha is supplied, retain the empirically
   verified finite range+.002 fallback. Fewer than four or constant observations
   do not supply this initialization.
3. Require strict support under the actual fixed theta. For a free alpha, also
   require an admissible positive beta shape start from the first two moments
   at the supplied/fitted endpoints. This is a conservative verified
   initialization policy, not a claim to have recovered SAS's internal shape
   iteration. Its known exception is recorded below.
4. Preserve a supplied alpha exactly; otherwise compute its conditional optimum
   from the transformed logarithms.

Two new reason tags make the contract accurate:

- `initialization_failed`, with no `best`, when this initialization cannot supply
  an admissible fit. Invalid raw samples retain their existing failure tags.
- `nonstationary_candidate`, with finite `best` parameters/log-likelihood, for
  a returned estimated-scale curve. It is **never** labelled mathematically
  converged. The adapter must retain the status/warning alongside the curve.

`Result`, `Fixed`, and `Curve` field layouts otherwise retain the existing API.
The private numerical budget is not repurposed as a SAS power MAXITER control.
No changes to joint-theta, beta, Pareto, parser, PROC or dev4's adapter were made.

## Regression evidence and precise limits

The runnable fixture contains all **85** fixed-theta cases, including failures
and the counterexample. **84 match** returned-curve presence and parameters;
**one remains explicitly unresolved**. The test checks the unresolved count and
identity instead of silently converting the SAS curve into a failure golden or
omitting that row. These counts are acceptance evidence, separate from a green
unit-test count.

All matched sigma values agree to numerical roundoff; tests allow
1e-10*(1+sigma) for normalization/translation arithmetic. Supplied theta and
alpha are checked exactly. Free-alpha agreement uses 5e-5 absolute tolerance,
covering SAS's finite shape iteration; the earlier grid's largest difference
was 4.27e-5. New admissible prospective scale errors are at most 5.83e-16 and
shape differences at most 5.29e-7. Every published candidate has strict support
and finite log-likelihood.

The old test expecting sigma=max(x)-theta has been replaced with the M9-derived
moment candidate for the same sample. It now expects sigma=.9716969696969697
and explicit `nonstationary_candidate` status, rather than accepting the wrong
boundary vector merely because it had a warning. The fixture and oracle output
changes are committed separately with that evidence rationale.

Known fixed-theta gap: for (1,5,5,5,5,5,5,5,9), theta=.9999 and both sigma/alpha
estimated, the four-moment beta pilot is inadmissible, but SAS returns
sigma=8.002, alpha=.5574860401002018. The helper still returns
initialization_failed. Comparable inadmissible cases are suppressed in SAS,
while supplying alpha allows a range+.002 curve. No sample-specific exception
was added to conceal this remaining initialization/fallback distinction.

## Free-location hypothesis: not implemented

The prospective probe also tested

    theta_candidate = min(x) - min(.001, .1*(min(x)-moment_beta_theta)).

It matches several large-unit cases, but fails on smaller-unit stopped fits.
For the new n=29 beta(.6,1.4) sample at unit scale, the candidate is
.000604830316486, whereas both free-theta requests return approximately
.000117642585607. At scale .1 and offset -4, the joint-location discrepancy is
about -.000905496. The n=59 power(.35) joint-location discrepancy at unit scale
is about -.000823117. The scale candidate continues to agree in these joint
requests, but that does not validate the location rule or full joint fit.
Scaled/translated results and residuals are retained in the audit. No guessed
location constant or substitution was added to production code.

## Small-unit beta controls

`feasible-start-controls.sas` uses the existing n=31 beta(2,3) sample scaled by
.01, with fixed second shape 1.5. These are **different constrained fits**, not
an undocumented way to set optimizer starts. Results:

| Separate request | SAS result |
|---|---|
| theta=0, sigma and alpha estimated | no curve |
| theta=0, alpha fixed at 2, sigma estimated | sigma=.008308475848110538 |
| theta=0, sigma fixed to infeasible pilot .007819202074319 | support error |
| theta=0, sigma fixed to feasible moment width .00975402321213 | alpha=1.248422413140384 |
| theta=0, sigma fixed to 1.05*max(x) | alpha=1.4339580423682468 |
| theta near minimum, sigma and alpha estimated | no curve |
| same near-minimum theta, sigma fixed to the now-feasible pilot | alpha=1.099064681319019 |

The run has one intentional support error and nine warnings. Fixing either
shape or a feasible scale makes the conditional problem solvable. Giving theta
a value that makes the scale candidate feasible still does not make the jointly
estimated shape/scale problem return a curve. Thus inadequate initial support
alone does not explain the failure; the coupling/stopping or shape initialization
remains unresolved. These controls do not identify the private algorithm.

Remaining in scope: the recorded inadmissible-pilot/free-alpha exception,
free/joint-theta power stopping, beta's coupled small-unit failure, and Pareto's
nonregular fallback selection. The fixed-theta improvement does not waive any
of these or mark the parent accepted.
