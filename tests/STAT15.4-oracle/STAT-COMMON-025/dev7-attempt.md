# COMMON025 — GLM ESTIMATE coefficient mapping and inference

Read the assigned ticket and original README/program/expected/log, S154 physical
pp.472–489, GLM-specific pp.4070–4071, and coefficient construction pp.4127–4128.
The original oracle source and expected output are unchanged.

## Applicable contract

Physical p.472 explicitly excludes GLM from Chapter20's shared ESTIMATE syntax
and directs readers to its procedure chapter. For GLM the label is required and
quoted; coefficients are positional; the ESTIMATE options are DIVISOR, E and
SINGULAR. Multirow/nonpositional specifications and ADJUST/EXP/JOINT are not
silently accepted as GLM options. Their negative cases use captured diagnostics.
MODEL CLPARM remains a separate unsupported MODEL feature.

The new `glm_estimate` module parses typed terms (effect IDs plus signed finite
coefficients), resolves the actual full-coded parameter columns, constructs L,
and calls COMMON009's estimability/inference helper. The original example maps
to `[0,-1,1,0]` in Intercept/group A/group B/x order. It does not apply those
coefficients to the computational sum-to-zero contrasts.

The full-coded design and rank-aware fit have been extracted from LSMEANS into
reusable `glm_estimability.codedDesign` and `fitCoded` helpers. Both consumers
now use the same column labels, order, empty-cell rules, numerical rank checks,
frequency/precision weighting, and full-model residual DF/MSE. No new numerical
solver or fixture-specific statistics were introduced.

Short coefficient lists zero-fill; extra coefficients warn and are ignored,
as specified on p.4127. Omitted higher-order CLASS effects receive coefficients
from the most specific explicitly supplied contained effect. An explicit zero
higher-order effect suppresses this filling. Intercept distribution follows
p.4128. Tied most-specific sources require an explicit higher-order effect and
fail loudly rather than guessing which source was intended. DIVISOR scales L
before evaluation; zero/nonfinite divisors and invalid SINGULAR values fail.

A typed nonestimable result retains null estimate/variance/SE/t/p fields and
prints `Non-est . . .`. A saturated but estimable function retains its estimate
with missing error-based inference. A genuine zero remains numeric zero.

E tables appear after Class Level/Observations and before the response ANOVA;
estimate results follow the model tables, matching the original full listing.
Computation is prepared once per response, even under NOPRINT, and rendering
receives typed tables. Existing render callers retain a compatible wrapper.

## Discriminating verification

The unchanged original matches all **151 tokens**, status 0, empty stderr;
whitespace is the only normalization. `verify.py` also computes independent
within-group ANCOVA crossproducts with exact rationals: slope 17/10, adjusted
B-minus-A 79/30, error SS 581/60, residual DF 9, variance factor 143/105, and
estimate variance 11869/8100. Its two-sided t probability uses an elementary
cosine-power integral for odd DF, independent of production beta functions.

Typed tests cover the original parameter labels/L vector, analytic estimate,
variance/SE/t/p, negative scaling and divisors, MODEL/CLASS ordering, omitted
coefficients, warning-and-ignore extra coefficients, true Non-est fields,
higher-order filling versus explicit zero, slice contrasts, saturated inference,
malformed and nonfinite coefficients, invalid options, and GLM applicability.
The new corpus source is a byte-identical copy of the original oracle; its new
compact golden has exactly the original SAS listing's tokens. No existing
expected files were rewritten.

## Ownership and remaining limits

Shared edits are limited to ESTIMATE parse/execution/render hooks and factoring
out the previously owned LSMEANS coded-fit helper. No SS3/SS4 or ABSORB algorithms,
main/root, board or skill changes. ABSORB+ESTIMATE fails explicitly until its
residualized/full-parameter basis mapping is coordinated with dev2. Interactive
post-RUN ESTIMATE remains an explicit gap in dev2's session boundary.

Other existing GLM limits remain: nested/mixed-class-covariate designs, tied
higher-effect fill sources, and ORDER=FREQ combined with a FREQ statement are
unsupported for these coefficient statements. This ticket does not install
GLM ESTIMATE syntax in other procedures or claim Chapter20 multiplicity-adjusted
inference for GLM. Final SHA/base, original replay, and direct-exit gate counts
are reported in the handoff after rebasing onto the manager branch.
