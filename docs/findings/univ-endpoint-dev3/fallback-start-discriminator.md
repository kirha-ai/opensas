# Width fallback versus shape start: prospective rejection and coupling control

No generic production change is justified by this pass. The fixed-theta
inadmissible-four-moment/free-alpha fallback remains unresolved as a class,
not just as one symmetric sample. No case-specific rule was introduced.

## Separate hypotheses, replayed against all 85 existing rows

`power-fallback-model.py` first retains the recovered width when four-moment
geometry is admissible, and otherwise tests range+.002 as the width fallback.
For fixed returned endpoints, let m and v be the conditional sample mean and
n-1 variance of y=(x-theta)/sigma. The two-moment beta shape start tested is

    a0 = m * (m*(1-m)/v - 1).

Four alternative return/no-return hypotheses were evaluated independently:

- positive conditional two-moment start;
- positive first shape Newton proposal from a0;
- positive first proposal from the default value one;
- positive first proposal from min(a0,1), with a0 required positive.

For the power shape score the first proposal is a*(2+a*mean(log(y))). This
specifies the hypotheses being tested; it is not a claim that SAS uses this
particular iteration, clipping, or starting value. Supplied alpha bypasses
these shape-start checks. Samples too small/constant to supply a width remain
failures in every model.

The retained 85-row fixture is replayed in full, including its known unresolved
SAS-returned curve. No row is dropped and its oracle result is not replaced by
current helper output. The clipped-start alternative fits all old outcomes and
all returned widths (maximum absolute scale residual 5.83e-16). Its conditional
alpha calculation differs from old SAS values by at most 4.27e-5. That apparent
retrospective success was tested prospectively before any interpreter change.

## Prospective mixture and tie-weight tests

`generate-fallback-mixtures.py` froze 36 requests and all four model predictions
before running SAS. It varies center mass, endpoint tie weights, asymmetry,
small center jitter, theta-to-minimum gaps, replication, units and translation.
Four fixed-alpha requests control for the width stage independently of shape
estimation. All 36 have inadmissible four-moment beta geometry and a feasible
range+.002 width. SAS returns 23 curves and suppresses 13.

| Hypothesis | Mismatches / existing 85 | Mismatches / prospective 36 |
|---|---:|---:|
| Positive two-moment start | 1 | 13 |
| First proposal from raw two-moment start | 1 | 23 |
| First proposal from one | 2 | 6 |
| First proposal from clipped two-moment start | 0 | 11 |

All four hypotheses are rejected as generic compatibility rules. In particular,
the rule which fixes the old heavy-tail row without breaking the other old rows
fails eleven fresh cases. It is not adopted merely because it matches the old
fixture. The prospective JSON preserves the frozen predictions separately from
predictions recomputed on exact HEX16 input observations.

Concrete discriminators include:

- A positive two-moment start and positive proposed step do not ensure a curve:
  `mixture_000` (one low point, three center ties, one high point) has no curve.
- A raw two-moment first step can be inadmissible while SAS returns a curve:
  `mixture_007` is one such counterexample.
- `mixture_029`, an affine version of the formerly unresolved symmetric sample,
  is suppressed despite a feasible width and a conditional alpha above .5.
  The clipped/default-one proposal is safely positive, not a rounding tie.

All 23 returned scales equal range+.002 exactly in the recorded arithmetic.
Free-alpha discrepancies from the conditional optimum reach 9.67e-5. None of
this establishes a safe rule for deciding which of the 32 free-alpha requests
will return a curve. The current helper's explicit four-moment guard suppresses
19 of the new SAS-returned curves; this broader gap is retained in the audit.
The old compiled 84/85 count describes only the old fixture, not these new cases.

## Hypothesis-based switch: conditional blocks versus the joint beta path

The next hypothesis was deliberately narrower: if each conditional block fits
across unit scales, but the jointly free pair does not, the failure is specific
to their joint estimation path rather than lack of a conditional solution.

`beta-coupling.sas` uses the retained n=31 beta(2,3) observations with theta=0 and
second shape fixed to 1.5, under scale factors .01/.1/1. At each scale it requests:

- the jointly free alpha/sigma fit;
- five scale-only fits with alpha=.75,1,1.5,2,3 supplied;
- three shape-only fits with sigma=1.001,1.02,1.1 times the observed maximum.

These are separate constrained fits, **not optimizer-start options**.

| Request class | Scale .01 | Scale .1 | Scale 1 |
|---|---|---|---|
| Alpha and sigma free | no curve | curve | curve |
| Five fixed-alpha fits | 5/5 curves | 5/5 curves | 5/5 curves |
| Three fixed-sigma fits | 3/3 curves | 3/3 curves | 3/3 curves |

The independent conditional-score solver agrees with all nine shape-only alpha
values to 1.56e-15. All fifteen scale-only values agree within 4.90e-5 after
normalizing back to original units. The original smallest-unit joint failure
remains. Conditional solvability alone therefore does not recover joint start
repair, constraints, Hessian/step handling or stopping. The experiment does not
identify which of those internal mechanisms is responsible.

## Same separation on power

`power-conditional-controls.sas` fixes sigma to the feasible range+.002 width
for six retained mixtures, chosen to include joint successes and failures.
All six fixed-width requests return the conditional shape optimum, within
2.23e-16 of the independent closed form. This includes mixtures whose estimated-
width requests return no curve. Thus a failed estimated-width request cannot
be explained by claiming its conditional shape equation has no solution.
No alternate fixed-parameter fit was substituted into the interpreter's joint
request path.

## Reproduction and current status

All sources, exact observations, ODS HEX16 estimates, text results and logs have
unique absolute paths under this dev3 directory. The actual M9 runs used the
same authorized sasrun interface with explicit sibling output/log paths:

- fallback-mixtures: 0 errors, 26 warnings; 36 requests.
- beta-coupling: 0 errors, 2 warnings; 27 requests.
- power-conditional-controls: 0 errors, 0 warnings; 6 requests.

Fit-failure and absent-ODS-object warnings are both retained. Python audits use
only standard-library arithmetic and the oracle records, not the Zig optimizer.
Run `power-fallback-model.py`, `analyze-fallback-mixtures.py`, and
`analyze-beta-coupling.py` to reproduce the comparisons. Generators preserve the
prespecified requests; no parameter output is computed by case identifier.

This bounded pass rejects unsafe start-rule generalization and isolates a joint
estimation-path failure with concrete controls. It does not recover a safe
universal fallback selector. Production estimator behavior and its accepted tolerances
remain unchanged; its guard comment now describes the unresolved fallback
rather than claiming that invalid four-moment geometry forbids estimation. The parent ticket's remaining fixed-theta, joint-theta, beta
and Pareto compatibility gaps remain open; green repository tests are not an
acceptance waiver for the newly retained counterexamples.
