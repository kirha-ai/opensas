# FEAT-univ-distributions — dev5 inference checkpoint

**All assigned tabulated inference cases are implemented and oracle-verified.**
The parent ticket remains open. Simulation failure accounting awaits dev4's
multi-seed/count evidence and an agreed additive contract; see
SIMULATION-ACCOUNTING-CONTRACT.md. No Jira, parser, fitting, distribution,
PROC, ODS, or dev4 GOF files were edited.

## Standalone API

`src/stat/univ_edf_inference.zig` imports only std and the shared diagnostics.

- `Request`: family, estimated-parameter flags (true means estimated), and
  actual fitted/specified alpha, beta, sigma, c. Preserve unrounded shapes.
  Lognormal ZETA is scale and SIGMA is shape. Map Family by tag name or switch,
  not enum ordinal. Resolve SAS parameter defaults before constructing flags.
- `availability(Request)`: parameter/shape availability. Sample-size limits
  belong to `tabulated`; use returned nullable probabilities for publication.
- `tabulated(diags, request, Statistics{d,w2,a2}, original_n)`: returns optional
  `Probability{value,sign}` for each test, with exact/less/greater signs. Raw
  statistics are not overwritten by probability corrections.
- `Request.exponential_boundary_count`: number of observations equal to fitted
  exponential theta, after FREQ expansion. Fit on the complete sample, then
  filter these values only for EDF and pass original_n plus this count. Null
  defaults to one when theta is estimated and sigma fixed, zero otherwise.
  This includes fixed-threshold boundary values, not only estimated minima.
  See EVIDENCE-EXPONENTIAL-BOUNDARIES.md for the required adapter change and
  empty-slice handling. The current main adapter still needs this integration.
- `simulate`: existing strict seeded callback API, default 500 replicates.
  Caller resolves clock/default seed once. Callback generates/refits the null
  sample and returns raw statistics; errors propagate. Result includes counts
  and binomial standard errors. This strict entry point is not a claim that
  SAS never excludes expected numerical refit failures.
- `interpolate`: linear probability interpolation with stored bounds and signs.

## Implemented coverage

- All-known seven-family EDF tables; known-table A2 starts at five EDF values.
- Partial and fully estimated normal/fixed-threshold lognormal conventions.
- All exponential estimation masks and effective counts after boundary filtering.
- All gamma masks, including shape-dependent estimated-threshold surfaces.
- Beta estimated-shape surfaces (ordered shapes), actual M9 availability limits.
- All Weibull masks, including estimated-threshold surfaces.
- All lognormal masks, including the strict sigma<1 versus sigma>=1 split when
  theta/sigma are estimated and zeta fixed, tiny positive sigma, and sigma<3
  availability for estimated thresholds.
- Actual M9 has no estimated-power EDF output, even explicit ALPHA=EST below 5;
  all-known power works. This verified manual discrepancy is documented in
  EVIDENCE-POWER.md. Johnson EDF absence is also preserved.
- Strict simulation driver for Gumbel, IGAUSS, Pareto, Rayleigh, with seeded
  reproducibility and statistical comparisons. Their simulated A2 is available
  at n=2; the all-known tabulated A2 minimum must not leak into simulation.

No simulated substitute is used for a tabulated family. Tail bounds are checked
before interior intervals, preserving M9's non-monotone tail surfaces near
parameter boundaries. Unsupported method requests and invalid inputs fail via
captured diagnostics.

## Evidence and runnable checks

Actual manual: manager's docs/sas94-procedures-statistical.txt, printed
pp.307–341, 359–407, 431–459, especially Table 4.31 pp.447–448 and simulation
controls pp.332–333/446–447. Actual oracle version is 9.04.01M9P06052025.
M9 availability differences from the manual are documented, not waived.

The EVIDENCE-*.md files provide per-family formulas, successful SAS commands,
independent holdouts, exact counts, fit-failure outcomes, and integration notes.
Sources/output/logs are retained losslessly; regression text only normalizes
whitespace. All samples are synthetic. Original probes have unique absolute
paths under /tmp/opensas-dev5-edf-20261113 and
/tmp/opensas-dev5-edf-round2-20261113.

`zig test src/root.zig -lc --test-filter 'dev5 EDF'` runs the helper checks.
`zig build gate` includes them. `dev5_edf_*_replay.py` re-extracts the accepted
surfaces and compares retained oracle output; NumPy scripts use the bundled
Python path documented in the evidence. Final rebased SHA and full gate counts
are recorded in the checkpoint report, not inherited from an earlier run.

## Remaining owner coordination

- Dev4: exponential boundary filtering, unrounded fitted-shape mapping, public
  row/warning/ODS behavior, and estimated-family simulation adapter validation.
- Dev5 after evidence/contract confirmation: additive typed numerical-failure
  accounting API, preserving the current callback and fatal error propagation.
- Parent manager: full FEAT-univ-distributions acceptance and ticket closure.
