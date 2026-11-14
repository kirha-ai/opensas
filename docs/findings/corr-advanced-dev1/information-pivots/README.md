# Absolute information rank: bounded native discriminator

Status: the absolute rank mechanism is accepted under the existing public guard.
The full singular-boundary path is NOT accepted: a frozen candidate matches all
40 earlier cases but fails 4 of 18 independently generated holdouts. The guard
was not removed and FEAT-corr-advanced remains DOING.

## Native result that distinguishes the rank decisions

`three-scale.sas/txt` varies only integer frequency multipliers for the remaining
cases 3, 21 and 22. It also compares PROBIT and QUANTILE at their marginal
probabilities; those two functions are bit-identical in the tested inputs.

| Case | Base-frequency rho | 100x-frequency rho | SE in both |
|---|---:|---:|---:|
| 3 | -.99901846933219 | -.9999 | 0 |
| 21 | -.99634377908992 | -.999 | 0 |
| 22 | .98771303561774 | .999 | 0 |

A scale-relative decision alone cannot explain these changes. For case 22,
`native-information.sas/txt` constructs the full expected-information matrix
using actual SAS probabilities and derivatives, at the reported rho and the
marginal-limit thresholds. These are reconstructed information matrices, not
an extraction of undocumented internal PROC CORR state. The fourth Schur pivot
is approximately 8.662041195e-10 at base frequency; its relative eigenvalue is
about 1.0025e-11. Both standalone GINV and SWEEP retain large finite variance.

An **absolute information-pivot decision of 1e-8 was fixed before** running
`transition.sas/txt`. It predicts that multiplying frequency by 11 leaves the
pivot below the decision, whereas 12 puts it above. SAS does exactly that:
scales 8/10/11 stop at rho=.9877130356; scales 12/13/20 continue to rho=.999.
The additional `transition-refined.sas/txt` check retains the low-frequency result
at scale 11.5. The native pivot bounds are therefore

    11.5 * pivot < 1e-8 < 12 * pivot.

This is a prospective matrix-rank discriminator, not a cutoff fitted to the
reported correlation or SE. `SINGULAR=1e-16` and `.5` do not change it. A log
replay explains why: SAS warns that SINGULAR= is allowed only with PARTIAL.
The parser now emits that warning instead of silently implying it controls
polychoric information inversion.

All accepted probe runs have zero errors. The transition runs have two warnings
for the deliberately inapplicable SINGULAR options. Normal acceptance command:

    /Users/thomas/sas/bin/sasrun /absolute/dev1-corr-PROBE.sas -f text -o - -l /dev/null

The warning-only diagnostic replay saved a private log; only the relevant warning
text is retained here, not the full system log.

## Production change and deliberate safety boundary

`solveInformation` performs generalized coordinate elimination with the recovered
absolute decision, returning the retained rank. A dropped coordinate has zero
solution/variance. It validates shape and finite inputs/results; unavailable
numeric input does not become a fabricated zero variance. The native full-matrix
unit checks scales 11, 11.5 and 12, including the retained inverse at 12.

The production caller uses this rank-aware primitive, but retains its existing
loud tight-boundary guard. No new rho clipping, probability-rounding rule, or
SE-specific zero assignment was installed. All default/interior and other
previously published results are verified by the gate.

## Frozen candidate and independent counterexamples

The complete diagnostic candidate was frozen at SHA256
`1a20eb2ece302b2d304ac3d63eef79764b8d4da486ca60510b2512defe520585`
before the transition and new holdout runs. Its portable `candidate.py` changes
only reference paths and removes its command-line harness; the source archive
retains the original. It includes earlier experimental boundary-step rules
that are NOT claimed as accepted production behavior.

It passes all 40 earlier cases, preserving the previous 37 successes and fixing
the three original diagnostic failures. Then seed 20261114 generated 16 new
strict staircase tables across 2x3, 3x2, 3x3 and 4x4 dimensions, signs, labels,
frequency multipliers and convergence tolerances. Two predeclared nested-category
cases were added to check a different boundary shape. No cases were filtered.
`heldout.sas/txt/json` retain all 18; SAS reports zero errors/warnings.

The frozen candidate passes 14/18. Its four counterexamples are:

| Case | Candidate rho / SE | SAS rho / SE | Consequence |
|---|---|---|---|
| 1 | .9998132928 / 0 | .9999 / 0 | boundary-step mismatch |
| 8 | .9999 / 0 | .999999 / 0 | boundary-step mismatch |
| 17, nested | .9999999999959 / 2.43e-9 | .99999999 / 2.83414308596e-6 | finite SE and LR mismatch |
| 18, nested | -.9999999999993 / 5.95e-10 | -.9999999 / .000014374992 | finite SE and LR mismatch |

Tolerances stay explicit: zero/nonzero SE category must match exactly; singular
rho uses 5e-6 absolute (the earlier SAS invariance probe measured a 4.15e-6
spread), nonsingular rho 5e-8; finite SE must meet both 5e-6 absolute and 1e-4
relative; LR uses 1e-7 + 2e-9*N. The nested cases were not passed merely because
their coefficients both round to one.

`bound-progress.sas/txt` further shows a sequence of decimal boundary iterates
for the nested examples as CONVERGE tightens. Strict-monotonic, progressive-bound,
and fraction-to-boundary exploratory variants did not validate all cases; they
remain in the private archive and were not installed. No epsilon or rho table
was fitted to these failed holdouts.

## Reproduction and next bounded question

    python3 docs/findings/corr-advanced-dev1/information-pivots/verify.py

This checks the prospective pivot transition, all 40 old comparisons, and retains
the exact four new failures. It is not a full-acceptance claim.

The remaining question is the boundary-step convention, especially the nested
category cases' repeated near-one iterates and finite SEs. Native MAXITER traces
for those specific cases can distinguish how clipping/refinement is counted.
Keep the public guard until that convention and a new independent holdout pass.
