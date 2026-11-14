# Estimated-threshold lognormal EDF inference

All four parameter masks are implemented: theta alone, theta+zeta, theta+sigma,
and all three. Fixed-threshold cases retain their validated normal-transform
inference. Estimated-threshold tests require n>=10 and sigma<3; there is no
invented lower sigma cutoff. The direct boundary probe confirms sigma=3 is
unavailable, and records SAS version 9.04.01M9P06052025.

## Response surfaces and regime boundary

Each probability knot has a fitted/specified-shape log-critical surface. Terms
include powers and square roots of sigma, inverse powers for the theta-only
case, log(1+sigma), and 1/log(n) for the all-estimated case. Critical D divides
exp(surface) by sqrt(n); W2/A2 use exp(surface). Negative sigma powers are
factored with Horner division to avoid infinity-minus-infinity at tiny shapes.
All eleven table levels and their distinct endpoint signs are preserved.

When theta and sigma are estimated with zeta fixed, M9 has two regimes:
sigma<1 and sigma>=1. Do not round fitted sigma before selecting the regime.
The exact-boundary oracle tunes 60 synthetic fits and records HEX16 sigma.
55 fits (165 test rows) return exactly IEEE 1.0; their interior p-values match
the upper regime to 6.4e-15, while using the lower regime errs by up to .0151.
All 180 exact/near-boundary rows are embedded in the Zig regression.

## Validation

- Six calibration sources cover the full masks and varied shapes/sample sizes.
  The controlled samples separate shape effects from sample-size corrections;
  inference always uses actual SAS fitted shapes, not generator targets.
- The median sweep is retained as six successful jobs (0,1,2,30,31,32), covering
  540 brackets. A combined run hit the remote job limit and a later session
  disconnected; neither failed run is used as acceptance evidence. Every final
  retained median job has zero errors and zero warnings.
- Independent heldouts change sample sizes to 11/37/83/197, plotting positions,
  perturbation spacing, location and scale, and include shapes .03 through 2.95.
  All 61317 emitted rows match, max p error 2.62e-13, exact bound signs.
- All 180 sigma-one rows match, max p error 1.76e-14, exact signs.
- All 24 tiny-shape rows (.001 through .10001) reproduce M9's stored bounds,
  including its non-intuitive <.001 D/W2 results at very small positive sigma.
- A separate probe checks both sides of every median bracket. All 1056 rows
  with complete fits match the exact upper-bound value/sign. The remaining 24
  rows explicitly report incomplete fitted parameters and no EDF output; they
  are retained and checked as fit failures, not silently removed.

The heldout, exact-sigma, small-shape and two-sided-bound runs all have zero SAS
errors and zero warnings. Zig checks every listed row at 1e-10 for interior
probabilities and exact endpoint values/signs. Actual missing EDF objects and
fit failures remain in the complete logs; parameter fitting is dev4's scope.

Replay with bundled NumPy:

```
/Users/thomas/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/findings/univ-edf-dev5/dev5_edf_lognormal_replay.py
```

This re-extracts numerical coefficients and median cutoffs and checks all
independent outputs. It is offline deterministic calibration, not a simulated
probability substitute. Sources/output/logs are lossless; regression fixtures
only normalize whitespace. Original paths are unique under
/tmp/opensas-dev5-edf-round2-20261113. The initial all-mask source was run as
threshold-families.sas and is retained under the lognormal-theta name.
