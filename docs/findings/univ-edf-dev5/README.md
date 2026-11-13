# FEAT-univ-distributions — dev5 SUPPORT checkpoint

**Partial support, NOT full acceptance.** This tracker covers only the new
standalone inference helper. It does not waive the remaining EDF requirements.
No parser, fit, distribution, PROC, ODS, or dev4 GOF files were changed.

## API for dev4 integration

`src/stat/univ_edf_inference.zig` has no imports of unlanded modules.

- `Request`: local `Family`, explicit `Estimated` SAS-parameter flags (true
  means estimated), fitted/specified shapes `alpha`, `beta`, `sigma`, `c`.
  For lognormal, ZETA is scale and SIGMA is shape; MU applies to normal.
  Map Family by tag name or switch, not enum ordinals: this is an independent
  enum and does not promise the same ordinal order as the distribution module.
- `availability(Request) -> Available`: Table 4.31 D/W2/A2 mask, including
  strict shape boundaries and unavailable Johnson tests. It is not a promise
  that all available cases have implemented probability tables.
- `tabulated(diags, request, Statistics{d,w2,a2}, n) -> Result`: optional
  `Probability{value,sign}` for each test. `sign` is exact/less/greater.
  Input/raw statistics remain untouched. Null means SAS-unavailable, whereas
  an available but unimplemented case raises a captured diagnostic.
- `simulate(diags, request, observed, n, SimulationOptions, Simulator)`:
  Gumbel/IGAUSS/Pareto/Rayleigh bootstrap with default 500 replications and an
  explicit resolved u64 seed. Caller resolves omitted/time-of-day seed once.
  Callback receives context, std.Random, n, diagnostics; it draws n values
  from the fitted null, refits estimated parameters under the original fixed
  constraints, and returns raw EDF statistics. A failed fit propagates; no
  retry/discard silently changes the null distribution. Result includes the
  three probabilities, exceedance counts, standard errors, seed and samples.
  Dev4 must supply family generation/refitting callbacks and wire
  EDFSEED/EDFNSAMPLES. Their parsing and default seed resolution are not here.
- `interpolate`: linear interpolation between critical-value knots with exact
  table-endpoint values/signs; no tail extrapolation.

## Implemented and verified

- Table 4.31 availability for normal, lognormal, exponential, gamma, Weibull,
  beta, power; Monte Carlo families; Johnson absence.
- All-known seven-family probability tables and both-estimated normal/
  fixed-threshold lognormal tables (matching the existing dev4 convention).
- Both partial normal/lognormal cases: no finite-sample correction, no D;
  p bounds >.25 and <.0025, with distinct tables for the estimated parameter.
- Fixed-threshold Weibull, each of three estimation masks: no D. If both
  sigma/c estimated, multiply both quadratic statistics by 1+.2/sqrt(n).
  If only sigma estimated, W2 correction 1+.16/n and A2 correction 1+.3/n.
  If only c estimated, no correction. Bounds >.25 and <.01.
- Seeded callback simulation, count/m probabilities including zero, reproducible
  seed behavior, invalid controls and callback failure propagation.

- Estimated exponential tables now cover all three estimation masks, including
  separate >.500/>.250 bounds and effective n-1 when only theta is estimated.
  See EVIDENCE-EXPONENTIAL.md for independent validation and integration details.

- Fixed-threshold gamma now covers all three estimation masks with fitted-shape
  response surfaces. M9 requires alpha>1 and n>=10 for estimated gamma; see
  EVIDENCE-GAMMA-FIXED.md for direct availability and independent holdouts.

- Estimated beta now uses ordered fitted-shape response surfaces, with n>=10.
  EVIDENCE-BETA.md records 17628 independent numeric/bound checks.

- M9 estimated-power requests emit no EDF table, including explicit ALPHA=EST
  below 5. Fully known power remains supported. EVIDENCE-POWER.md documents
  the difference from Table 4.31; it is not an invented implementation exclusion.

- Estimated-threshold gamma now covers all four masks, with 30672 independent
  heldout rows. Tail bounds are checked before interior interpolation, matching
  M9 even when near-boundary critical surfaces are non-monotone. See
  EVIDENCE-GAMMA-THETA.md.

- Estimated-threshold Weibull now covers all four masks. 30294 numerical
  heldouts and 600 independent two-sided median checks pass. See
  EVIDENCE-WEIBULL-THETA.md.

## Concrete remaining gaps (full acceptance is NOT met)

- Estimated-threshold lognormal probabilities and their remaining shape surfaces.
  Availability is implemented, probability computation fails loudly where
  these documented-available combinations lack tables.
- Dev4 integration and generation/refitting callbacks. Statistical comparisons
  cover all four fixed-parameter simulation families and estimated-scale
  Rayleigh; estimated Gumbel/IGAUSS/Pareto callbacks are not independently
  validated here. This is not complete simulated-family acceptance.

## Evidence and reproduction

Read actual manual text from manager checkout:
`/Users/thomas/kirha/opensas/docs/sas94-procedures-statistical.txt`.
Reviewed EDF/parameter descriptions in printed pp.307–341, 359–407, 431–459;
Table 4.31 is pp.447–448. Pages 332–333 specify EDFNSAMPLES=500 and the
clock-derived default EDFSEED; pp.446–447 specify resampling and internal
probability tables with linear probability interpolation. The manual does not
publish the remaining internal critical tables. No invented approximation or
simulation substitute is supplied for the seven table-based families.

All probes use synthetic deterministic samples and SAS 9.4 M9:

```
/Users/thomas/sas/bin/sasrun /tmp/opensas-dev5-edf-20261113/tables.sas -f text -o - -l /dev/null
```

The same command was used for `dense.sas`, `heldout.sas`, and `mc.sas`.
Successful final runs each reported 0 errors and 0 warnings. Source and gzip
text output are retained here; heldout text is the runnable test fixture
`src/stat/testdata/univ_edf_dev5_heldout.txt`. Gzip is lossless, not a golden edit.

- `tables`: n=20/100/500, 161 perturbations for eight estimation cases.
- `dense`: 1601 perturbations for the same cases. `dev5-edf-knots.py` identifies
  consecutive equal-slope interpolation segments and prints their implied
  knots; it is an evidence analysis utility, not runtime calibration.
- `heldout`: n=37/83, 61 perturbations, different plotting positions and
  Weibull shapes .7/4; 1708 rows are checked directly against the Zig API,
  absolute p tolerance 1e-10 and exact bound signs. An initial generation
  formula `-log(1-u)` rounded tiny u to zero and caused 15 SAS support errors.
  Final source uses `-log1px(-u)` and runs cleanly; no failed-fit rows were
  filtered or waived. Heldouts caught and corrected the A2 .3/n coefficient.
- `mc`: seed 13579, 10,000 replications, repeated fixed Rayleigh run identical.
  New implementation seed 86531 uses an independent stream. Each comparison
  allows five pooled binomial standard errors plus one count; p near zero
  gets a one-count variance floor. Fixed-family callbacks use probability
  integral-transform invariance; estimated Rayleigh actually refits scale.
  A separate exploratory 20,000-draw check gave fitted-Rayleigh probabilities
  (.603,.22815,.12355) versus SAS (.6012,.2315,.1294); omitting refitting gave
  (.7801,.4952,.37045), demonstrating why refitting matters.

Runnable checks: `zig test src/root.zig -lc --test-filter 'dev5 EDF'` (six
helper tests plus root import test); `zig build gate` includes all checks.
The final report records exact gate counts and the green SHA. This evidence
checkpoint itself makes no claim that the full distribution ticket is done.
