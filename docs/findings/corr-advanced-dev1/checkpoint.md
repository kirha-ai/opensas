# Public integration handoff and preserved solver investigation

Hoeffding public inference is integrated through the landed support API. Its
implementation and SAS-backed golden are separate commits. ODS guards and the
support/root imports are preserved. The full parent ticket remains DOING solely
because tight-polychoric compatibility is not accepted.

The singular-information sources, stdout and verifier in this directory are
retained evidence. All later exploratory files are preserved in:

    /private/tmp/dev1-corr-checkpoint-20261113-53a13f9.tar.gz

They also remain individually under `/private/tmp/dev1-corr-*`. No experiment
was discarded or installed in production. The archive is kept outside Git
because it includes exploratory/debug logs as well as synthetic source/results.

## Exact remaining diagnostic outcome

A candidate using safeguarded information denominators, a singular inverse and
boundary-step handling was frozen before a fresh 40-case SAS run. The cases span
2x3, 3x2, 3x3 and 4x4 tables, signs, labels, frequency scales and two convergence
tolerances. Candidate source hash:

    ba750a275dfc1c36ec0eeb31069603b5eb3cb44a205616828445547424a7be7d

It passed 35/40, not full acceptance. Failed case IDs: 2, 3, 17, 21 and 22.
Two cases retained finite SE where SAS returned zero. The largest absolute rho
discrepancy was approximately .011287. The production tight-boundary guard is
unchanged; no numerical cutoff was installed from this unsuccessful candidate.

Fresh sources/results/predictions:

- `dev1-corr-singular-fresh.sas`, `.txt`, `.json`
- `dev1-corr-singular-general-predict.py`
- `dev1-corr-singular-fresh-predictions.json`

## One bounded continuation

Investigate fresh case 2's stopping check. Its candidate full scoring step at
iteration 15 is about .000365588, but backtracking scales it by .00048828125.
The accepted step is only 1.7851e-7, which currently triggers convergence at
rho=.9947336983, SE=.365588. Actual SAS with CONVERGE=1e-6 stays unconverged
through MAXITER=23, then succeeds at 24 with rho=.99785336020657, SE=0.

The already-completed discriminator is retained as:

- `dev1-corr-case2-step-diagnostic.py` and `.json`
- `dev1-corr-case2-stopping.sas`

Its SAS run completed with zero errors and 12 expected MAXITER warnings. The
same SAS point is returned at convergence tolerances 1e-4, 1e-5 and 1e-7.
Next determine whether convergence must use the full scoring step rather than
a line-search-shrunken step; do not broaden tolerances to hide the mismatch.
