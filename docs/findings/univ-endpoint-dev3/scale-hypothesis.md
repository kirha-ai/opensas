# Bounded refinement: a moment-derived width candidate

This is evidence for a narrowed mechanism, not recovery of the full SAS solver.
No production fitting rule or acceptance tolerance was changed. The parent
FEAT-univ-distributions ticket is still not done.

## Experimental boundary

Two prespecified batches, 73 requests total:

- `generate-scale-grid.py`: 53 cases. A dense unit grid for n=41 power shape .5;
  heldouts n=23/.5 and n=67/.8 around the **old** candidate .002/min(x) transition;
  fresh beta samples n=31 from beta(2,3) and n=53 from beta(.7,2), fitted with
  second shape fixed to 1.5 and .7 respectively.
- `generate-controlled-grid.py`: 20 cases. Duplicate each n=41 observation three
  or ten times; perturb the fitted second beta shape to .9, .99, 1.01, 1.1 and
  1.5; add small-unit n=23 and n=67 heldouts.

Both batches were generated before deriving the moment-width model. Each logs
actual input observations and returned ODS estimates in HEX16. The normal oracle
command with unique absolute dev3 source/output/log paths was used. Runs contain
zero errors, with 46 and 8 warnings respectively (fit failures and their absent
ODS-object warnings). There are 46 returned curves and 27 no-curve outcomes.

`analyze-scale-grid.py` is independent Python standard-library analysis. It
reconstructs exact inputs, computes corrected moments and conditional shape
roots, and writes `scale-grid-audit.json`. No case identifier controls a fitted
parameter or hides a counterexample. Its assertions validate the retained
experiment only; they do not claim universal solver equivalence.

## Rejected simple hypothesis

The unrestricted rule `sigma = range + .002` is false. For n=41 and scale factors
.02 through .4, the padding is proportional to the scale factor instead. The
simple support-box presence prediction has 11 counterexamples across the 73
requests, including the fresh power shape .8 and non-beta1 beta cases.

Repeating observations leaves the empirical distribution and support unchanged,
but changes the small-unit returned width:

| Copies of each observation | Returned sigma at scale .1 |
|---:|---:|
| 1 | .0974215744614950 |
| 3 | .09726270847764057 |
| 10 | .09721296188163198 |

This distinguishes a sample-size-dependent pilot from a rule based solely on
range, units or a fixed derivative-probe distance.

## Recovered candidate

Let R=max(x)-min(x), V be the n-1 sample variance, G the corrected sample
skewness and K the corrected sample excess kurtosis. The four-moment beta width
can be calculated without fitting any case-specific constants:

    T = (6 + 3*K - 3*G^2) / (1.5*G^2 - K)
    D = G^2*(T+2)^2 / (16*(T+1) + G^2*(T+2)^2)
    S_mom = 2 * sqrt(V*(T+1)/(1-D))

T is the moment estimate of alpha+beta and D is the squared normalized shape
imbalance. These expressions require valid beta-region moments; all samples in
this experiment satisfy that condition. The supported empirical candidate is

    S0 = R + min(.002, .1*(S_mom-R)).

The factor .1 was identified from the **same width/moment relation in all three
replication counts**, not from fitting a curve to sample index or unit scale.
The already-generated different-n/shape and non-beta1 observations then tested
it without changing either constant.

For all **53 power requests**, including the independent n=23 and n=67 samples:

- curve presence equals `S0 > max(x)-theta`;
- all 29 returned widths equal S0, maximum absolute difference 5.56e-17;
- with returned endpoints fixed, the analytical power shape optimum differs
  from SAS's reported alpha by at most 4.27e-5.

The dense n=41 transition is between scale 8.71 (curve) and 8.712 (no curve).
At 8.712, S0 equals the observed maximum exactly, so strict support fails.
For n=23, predictions hold on both sides of its independently generated
transition. For n=67/shape .8, the simpler range+.002 box is feasible in several
failed cases, but S0 is not; this explains that heldout failure split.

## Fresh beta validation and what remains unidentified

On fresh n=53 beta(.7,2) data fitted with second shape .7, successful widths at
scales .01/.1/1 equal S0 (maximum difference 1.39e-17); scales 10/100 fail as the
candidate becomes infeasible. Nearby second shapes .9/.99/1.01 also remain at
S0. Second shapes 1.1 and 1.5 can move above it to an interior scale optimum.
Thus S0 is a plausible **initial width or internal floor**, not a universal final
scale formula, and not a documented distribution-support constraint.

An independently profiled candidate policy was also checked: optimize shape at
fixed endpoints; for second shape <=1, attempt S0 and reject invalid support;
for second shape >1, optimize the profile above the candidate/physical support
floor. This is a hypothesis model, not the interpreter's fitting implementation.
It predicts 72/73 presence outcomes; across all returned curves its largest
normalized scale discrepancy is 1.424e-5. The largest conditional shape
residual over all returned power and beta curves is 1.277e-4.

The retained counterexample is `grid_043`: n=31 beta(2,3), scale .01, fitted
second shape 1.5. S0=.007819202074319012 is initially infeasible, but a finite
profile optimum exists at sigma=.008371957092987683. SAS returns no curve.
The same sample at scales .1/1/10/100 converges above an initially infeasible
candidate. Therefore a generic moment-width floor **does not recover the
feasibility-repair or stopping/failure policy**. No special-case switch was added.

The experiments cannot yet distinguish “initial point retained at stopping”
from “active internal lower bound” in the boundary-return cases. They do narrow
both alternatives to the same sample-moment-based width construction. They do
not recover initialization of a free theta, or Pareto's separate nonregular
fallback policy. No further blind algorithm search was undertaken.

## Primary documentation and finite-difference hypothesis

[SAS/STAT 14.1 NLMIXED: finite differences](https://support.sas.com/documentation/cdl/en/statug/68162/HTML/default/statug_nlmixed_details18.htm)
gives default steps sqrt(epsilon)*(1+abs(parameter)) for forward first
 derivatives and cbrt(epsilon)*(1+abs(parameter)) for central formulas and
function-based second derivatives. FDIGITS can replace machine precision.
These default magnitudes do not identify the observed moment-dependent padding.
Five successful oracle fits would put a default central scale probe outside
support, which also prevents treating simple central-probe feasibility as the
curve-presence rule. This does not exclude adaptive or one-sided probing.

[SAS/IML 14.1: control parameters](https://support.sas.com/documentation/cdl/en/imlug/68150/HTML/default/imlug_nonlinearoptexpls_sect024.htm)
describes algorithm-dependent initial steps/trust-region radii, line searches,
finite-difference accuracy and constraint tolerances. Its default initial
step/factor is 1, and constraint tolerances can change during optimization.
These are relevant mechanisms, but neither source establishes which algorithm,
derivatives, scaling, or defaults UNIVARIATE uses internally for beta/power.
Using those general defaults as an undocumented UNIVARIATE specification would
be unjustified.

## Result

A testable narrowed mechanism remains: the exact moment-derived width candidate,
validated on independent sample sizes, non-beta1 shapes and replication. Its role
as initialization versus bound, and the small-unit feasibility-repair failure,
remain unresolved. This is useful implementation evidence, not full optimizer
recovery or a reason to declare mismatched default output compatible.
