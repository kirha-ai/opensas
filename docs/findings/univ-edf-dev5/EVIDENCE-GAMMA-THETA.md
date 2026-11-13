# Estimated-threshold gamma EDF inference

All four estimated-threshold masks now have tabulated probabilities: theta
alone, theta+sigma, theta+alpha, and all three. Combined with the fixed-threshold
helper, every gamma estimation mask is handled. Actual M9 availability is
alpha>1 and n>=10 for any estimated parameter; all-known gamma retains its
separate complete-null table.

Response surfaces are family/statistic-specific: most use powers of 1/alpha,
1/sqrt(n) and 1/n. Theta+sigma W2 additionally uses 1/log(n) and
1/(sqrt(alpha)*log(n)); all-three estimation includes cubic 1/n corrections.
These terms were identified and verified from M9 equations, not replaced with
a generic finite-sample factor. Coefficients and explicit bases are in the
helper, and the extraction replay retains every calibration record.

## Numerical evidence

Three calibration sources cover known alpha values 1.2 through 20, n=10
through 1000, and actual estimated shapes up to about 103. The known-shape
runs have zero errors/warnings. The estimated-shape run has zero errors and
four SAS invalid-ALPHA warnings; it retains every emitted EDF record. The
source does not manufacture statistics for SAS fits that fail.

The separate median probe brackets all 300 mask/statistic/shape/sample-size
cutoffs. All 300 cutoff equalities agree with the response surfaces; no
calibration point is excluded. The median run has zero errors/warnings.

Independent holdouts use n=11/37/83/197, generator shapes 1.05/2.3/7/30, new
rank offsets and perturbation spacing, and affine changes to location/scale.
All **30672 emitted rows** agree to maximum p error **2.23e-13** with exact
stored probability values and bound signs. Zig checks all rows at 1e-10.
M9 separately reports 74 groups with no available EDF statistics and six
invalid-ALPHA fit warnings; there are zero SAS errors. These are actual oracle
outcomes, not helper exclusions. Fitting and public warning rendering remain
owned by dev4.

Near alpha=1, some M9 critical surfaces have non-monotone tail knots. M9 checks
the final <.001 bound before searching interior intervals. The independent
alpha=1.05 holdouts exposed nine cases where interpolating first would invent
an interior probability. The helper now preserves the endpoint check order;
it never sorts these tables or extrapolates beyond their stated tail bounds.

Replay with bundled NumPy:

```
/Users/thomas/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/findings/univ-edf-dev5/dev5_edf_gamma_theta_replay.py
```

All retained oracle sources/output/logs use synthetic data and unique original
paths under `/tmp/opensas-dev5-edf-round2-20261113`. Expected regression text is
only whitespace-normalized SAS output. The helper does not import fitting,
parser, renderer or ODS modules; its API is unchanged.
