# Sparse polychoric boundary follow-up — dev1

Status: default/loose sparse inference accepted on the cases below; tight-tolerance
boundary information remains an explicit error. FEAT-corr-advanced is not DONE.
No Hoeffding probability work was duplicated; that support belongs to dev5.

## Numerical change

`corr_polychoric.zig` now integrates each bivariate-normal rectangle as a positive
one-dimensional conditional-normal integral. It splits at the conditional-normal
transitions before adaptive quadrature, avoiding subtraction of four almost-equal
CDFs near |rho|=1. Analytic derivatives replace finite differences of rectangle
probabilities and the likelihood. Normal tails use direct erfc rather than 1-CDF.

SAS probes discriminated three additional solver conventions:

1. Start rho at the frequency-weighted Pearson correlation of the original
   numerical category values, not zero or merely the category indices.
2. Use Fisher scoring with absolute parameter-change convergence. The covariance
   is the inverse information at the final scoring linearization, before its last
   update. Re-evaluating at the updated rho produces a different, unstable SE.
3. A proposed rho outside [-1,1] restarts at +/-0.999. The one-iteration label
   probe gives rho=.999, SE=.12853158043271, LR=40.901334150979. Halving the whole
   parameter step instead gives a different trajectory and fails held-out tests.

These rules are verified by SAS outputs, not inferred solely from the balanced
3x3 case. Other FREQ modules and ODS infrastructure were not modified.

## Oracle checks

Commands use unique absolute temporary paths, for example:

    /Users/thomas/sas/bin/sasrun /private/tmp/dev1-corr-sparse-heldout.sas -f text -o - -l /dev/null

Retained source/stdout pairs:

- `sparse-sensitivity`: N=31 staircase counts [10,4,0;0,8,2;0,0,7], CONVERGE
  .001/.0001/.00001/.000001, MAXITER 5/10/15. Two expected iteration warnings.
- `sparse-heldout`: reverse sign, transpose, nonuniform labels, and a different
  staircase [5,7,0;0,8,3;0,0,12]. Zero errors/warnings.
- `boundary-fixture`: all accepted corpus cases, including the discriminating
  one-iteration nonuniform-label case. Zero errors/warnings.

| Case | SAS rho | SAS SE | Runnable tolerance |
|---|---:|---:|---|
| Original, default .0001 | .9990304484694 | .1169549768335 | rho 5e-8; SE 5e-7 |
| Original, loose .001 | .99729481288087 | .01781882037824 | rho 5e-8; SE 5e-7 |
| Sign reversed | -.99903044846942 | .11695497683919 | rho 5e-8; SE 5e-7 |
| Transposed | .99903044846893 | .11695497655443 | rho 5e-8; SE 5e-7 |
| Labels 100,101,1000 | .99915910281921 | .21383503532071 | rho 5e-8; SE 5e-6 |
| Labels, first iteration | .999 | .12853158043271 | rho 1e-10; SE 5e-8 |
| Held-out N=35 table | .99894222793371 | .21987585371233 | rho 5e-8; SE 5e-6 |

The original table's LR=40.9081053981301 is tested to 1e-7 absolute; its
Wald=72.965915384262 to 1e-3 absolute. Small SE differences amplify in the Wald
statistic: current compact output 72.96610 is not a claim of four-decimal SAS
agreement. The tiny Wald p=1.3190831196899e-17 is checked to 1e-3 relative, with
no hard tail cutoff. MAXITER 5/10 produce missing estimates; default converges
in 11 iterations and MAXITER 15 succeeds, consistent with SAS.

An independent numerical regression compares quadrant probabilities against
1/4 + asin(rho)/(2*pi) through rho=+/-0.999999 (5e-11 absolute). It also checks
that a separated near-boundary rectangle retains a positive small probability.

## Remaining limitation, not an exclusion from the ticket

For the original staircase with CONVERGE=1e-5 or 1e-6, SAS reports
rho=.99985326007584, SE=0 and missing Wald inference, with LR=40.9081058800832.
Unprotected floating-point iterations with positive rectangles can instead report
large finite SEs (thousands or more). Publishing those as SAS-compatible would
be incorrect.

For monotone-support tables, the saturated multinomial likelihood is the exact
rho=+/-1 likelihood limit. When the current likelihood is indistinguishable from
that limit at the rectangle integration error budget (N*1e-10), the solver reports
unresolved boundary information. The procedure raises a captured diagnostic;
it does not publish an arbitrary finite SE or a fabricated zero. This is a
numerical-resolution check, not a fixed rho cutoff or a blanket sparse-table ban.
Reproducing SAS's tight-tolerance singular-information convention remains open.

The positive-rectangle/Fisher-scoring path now handles the original default
failure (old SE~680552) and the held-out cases. The blanket sparse guard is removed.
CORR grammar annotations were updated only within the CORR section. New/changed
corpus expected outputs are committed separately, justified by these SAS probes
and the retained original balanced-table oracle.
