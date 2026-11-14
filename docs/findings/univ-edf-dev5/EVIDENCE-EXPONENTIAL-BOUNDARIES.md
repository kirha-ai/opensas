# EDF boundary observations and effective sample sizes

Actual M9 excludes every observation equal to the fitted exponential threshold
from EDF statistics, including when the threshold is supplied. Parameter
estimation still uses the complete original sample. The probability calculation
uses the remaining EDF count. This applies to fixed, scale-estimated and
threshold-estimated requests; the both-estimated probes have no excluded values
because their bias-corrected threshold lies below the minimum.

## Adapter contract for dev4

After fitting on the full sorted/FREQ-expanded x:

1. For an exponential curve, count the leading values equal to distribution.p.theta.
2. Compute raw EDF statistics on the remaining slice. Do not refit that slice.
3. Pass original x.len and `Request.exponential_boundary_count = excluded_count`
   to `tabulated`. The nullable field defaults to one for theta estimated /
   sigma fixed (distinct-sample compatibility), zero otherwise. Explicitly
   supply the count for boundary observations or ties.
4. With no remaining EDF observations, publish no GOF rows and do not unwrap
   an empty raw-EDF result. Returned nullable probabilities are authoritative
   for sample-size availability; availability(Request) is parameter-based.

The helper change is backward compatible. It does not edit the adapter. The
currently landed univ_distribution_gof.compute still computes raw statistics
on unfiltered x; dev4 must apply the contract above.

## M9 evidence

- `exp-tie-inference`: 1098 EDF rows, remaining counts 10/30, excluded counts
  1/2/5 and 61 perturbations. Using n minus all excluded minima matches every
  stored probability and sign (max error 2.75e-11). Using n-1 instead gives
  349 mismatches, including wrong upper bounds.
- `exp-boundary-masks`: 36 rows contrast all four parameter masks with one,
  two and three tied minima. They match the helper at 1e-10. With known theta=1,
  estimating sigma from x=1,...,10 gives sigma=4.5 from all ten observations;
  EDF uses the remaining nine, W2=.20612584565148 and p=.0610498063026.
- `exp-min-ties`: independent raw-statistic check; all tied minima disappear,
  and A2 remains finite. Removing only one of several minima is incorrect.
- `exp-tie-minimum`: estimated-parameter EDF tables require at least five
  remaining observations, regardless of how many boundary values were excluded.
- `exp-boundary-minimum`: all-known D/W2 remain available with one EDF value;
  all-known A2 starts at five. For one EDF midpoint, W2=1/12 and M9's stored
  probability is .02798611111111. This follows M9's table correction.
- The previously retained `minimum-n` experiment independently confirms the
  all-known A2 restriction for normal, beta, gamma and Weibull. Partial/fitted
  normal and fixed-threshold Weibull retain their A2 tests at smaller n.
- `edf-mc-minimum` confirms all three simulated tests are available at n=2
  through 6 for Gumbel, IGAUSS, Pareto and Rayleigh. The tabulated all-known A2
  restriction must not be applied to simulation.

All six new oracle runs have zero errors and zero warnings. Sources, outputs
and logs are retained losslessly. Original paths are unique under
/tmp/opensas-dev5-edf-round2-20261113. Zig regression fixtures check the 1098
and 36 rows and captured diagnostics reject impossible boundary counts.
