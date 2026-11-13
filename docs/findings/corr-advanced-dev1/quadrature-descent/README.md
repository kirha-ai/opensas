# Case 2: quadrature error was mistaken for convergence

Status: the numerical integration defect is fixed and independently checked.
The experimental tight-boundary solver now passes 37/40 existing cases, retaining
all previous 35 passes. Cases 3, 21 and 22 remain failures. The production
singular-information guard is unchanged; FEAT-corr-advanced remains DOING.

## Bounded discriminator

At case 2 iteration 15, the full scoring change is .000365588002, but the
accepted backtracked change is only 1.7851e-7. Changing the stopping test to the
full change prevents false convergence, but then the line search stalls.
It does not fix the likelihood calculation and was not installed in production.

An audit at the fixed states before and after that full step found:

| Quantity | Old Simpson result | Independent marginal/CDF reference |
|---|---:|---:|
| Sum of six rectangle probabilities, before | 1.000000001690196 | 1 |
| First occupied cell, before | .31007752107010123 | .31007751937984379 |
| Negative log likelihood, before | 1227.6442876276392 | 1227.6442891538863 |
| Negative log likelihood, full step | 1227.6442884965961 | 1227.6442884965318 |

The old estimator accepted an inaccurate panel. It made a genuinely descending
step appear worse, causing severe backtracking and then false convergence.
The new Zig regression fails on the old code by about 1.69e-9 in a probability
whose transposition should be identical (tolerance 3e-13).

## Corrected generic mechanism

Positive conditional-normal rectangle integration and transition splitting stay
in place. The embedded 7-point Gauss / 15-point Kronrod rule replaces the
Simpson panel estimate. Its error estimate includes variation and a roundoff
floor. The largest-error panel is split until the estimated total error meets
the existing 1e-10 relative budget. The budget is recomputed from the current
estimate rather than subdividing an underestimated initial budget forever.

A subdivision or roundoff limit returns missing numerical output, which the
solver treats as nonconvergence. It does not silently accept an unresolved panel
or omit a nonfinite occupied-cell probability. The likelihood and score still use the actual probability. A separate,
previously recovered information-denominator floor of 1e-12 is now also applied
in production. That constant was fixed in the original candidate before the
40-case oracle, not fitted to these new outputs. With quadrature alone the
first finite-SE probe gives .2473138842 rather than SAS .2473165057; applying
the recovered information safeguard passes both preset 5e-7 SE checks.
The CONVERGE value, rank rule and rho boundary convention are unchanged.
The stopping normalization is corrected as established below.

Mathematical rule reference (weights and error-estimation method):
https://jacobwilliams.github.io/quadpack/proc/dqk15.html
Original QUADPACK DQK15 reference: https://netlib.org/quadpack/dqk15.f
The implementation is a local Zig panel evaluator and global refinement loop,
not a new dependency. No unrelated shared numerical module was changed.

## Actual SAS 9.4 M9 checks

`case2-rectangle-oracle.sas/txt` evaluates the same fixed states with SAS
PROBBNRM. Both probability partitions sum to 1, and the likelihoods above agree
within 5e-9. This is a reference evaluation of the existing failing case, not a
new independent solver holdout. It reports zero errors/warnings.

`public-precision.sas/txt` verifies public CORR calls for that same data:

| CONVERGE / MAXITER | SAS rho | SAS SE | SAS LR |
|---|---:|---:|---:|
| .00045 / 14 | .99473351980195 | .24731650570926 | 633.376921745778 |
| .00038 / 15 | .99509910781704 | .36558803940963 | 633.376923060487 |

The old quadrature could falsely trigger the unresolved-information guard for
these valid finite-SE requests. The corrected quadrature supports both without
weakening the guard. Runnable public tests use 5e-8 rho, 5e-7 SE, 1e-7 LR and
5e-8 probability tolerances. The public corpus fixture pins their compact listing;
its golden is committed separately with the retained SAS evidence.

Commands used unique absolute temporary files:

    /Users/thomas/sas/bin/sasrun /private/tmp/dev1-corr-case2-rectangle-oracle.sas -f text -o - -l /dev/null
    /Users/thomas/sas/bin/sasrun /private/tmp/dev1-corr-quadrature-public-precision.sas -f text -o - -l /dev/null

The latter run also reports zero errors/warnings. The corrected kernel was frozen
before it at SHA256 87d50b2493ca71e57284feca3debddba653259407103f5df4a9173b31e9b7081.

## Existing case set, no hidden exclusions

`cases.json` and `oracle.sas/txt` retain all 40 earlier SAS cases. `candidate.py`
is the same diagnostic mechanism before/after, with only the quadrature module
swapped by `verify.py`. Run:

    python3 docs/findings/corr-advanced-dev1/quadrature-descent/verify.py

It checks that all previous 35 passes remain and that the failure set shrinks
from {2,3,17,21,22} to {3,21,22}. It also checks the fixed-state partition,
transposition and descent identities. The prototype is not production code and
is not a full-acceptance claim. No fresh independent case set was generated
while known failures remain.

Other investigated changes were rejected: using the full step alone stalls the
line search; dropping the represented-probability uncertainty check regresses
previously passing cases; angular information scaling also regresses cases.
These variants remain in the private research archive, not production.

The remaining issue is the singular-information/iteration convention for cases
3, 21 and 22. In particular, the case-22 native-information probe returns large
finite variance from both standalone GINV and SWEEP where PROC CORR reports SE=0.
That supports further discrimination, not a fitted zero-variance cutoff.

## Stopping norm and final independent controls

The initial combined-kernel freeze was
`e5ba857849b1522afdfe6977b02581759f87ee8f9d9bef3575481a1edf8c9f3e`.
The first control then exposed an additional mismatch: absolute-maximum stopping
ended at iteration 4 with rho=.7335717556787, while SAS first succeeds at 5 with
rho=.73357532289915. That run became discovery, not a passing held-out claim.

`interior-convergence.sas/txt` and `interior-norm.sas/txt` distinguish norms:
at iteration 4, max change is 4.8099e-5, L2 is 7.3685e-5, L1 is .00013120,
but maximum relative change is .00065754. SAS still goes to iteration 5 at
CONVERGE=.0002, excluding the first three norms. The existing FREQ-style rule
uses relative change except for old estimates below .01 in absolute value.
`relative-fallback.sas/txt` confirms its near-zero fallback: SAS succeeds at 4,
where a fully relative check would need 5. This corrects the earlier
absolute-only assumption in CORR; FREQ itself was not edited.

The 3x2 and 2x3 control values remain direct runnable checks:

- N=90, default: rho=.73357532289915, SE=.0836568956254,
  LR=32.2741142794848.
- N=95, CONVERGE=1e-6: rho=.80508700896629, SE=.06662433183458,
  LR=43.9079638988586.

The final combined mechanism was then frozen at
`50a55fe00d7420581150665a2988a00c38be7c271d26c9fc7fc77ad7599bbc57`
before `quadrature-final-controls-precision.sas/txt`, two new predeclared full
count tables not used to select any rule. This run reports zero errors/warnings:

- 3x3, N=74, default: rho=.64919651354426, SE=.093706839039,
  LR=24.0452695361532.
- 2x2, N=52, CONVERGE=1e-6: rho=.60674978943585, SE=.16026513167272,
  LR=8.93456112392664.

All four controls pass public unit checks at 5e-8 rho, 5e-7 SE and 1e-7 LR and
are included in the corpus fixture. The diagnostic 40-case comparison also
retains 37/40 with corrected stopping; the same three failures remain.
These bounded validations do not claim full tight-boundary acceptance.
