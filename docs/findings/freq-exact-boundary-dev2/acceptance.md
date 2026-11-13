# dev2 FEAT-freq-exact numerical support — not ready

Assignment baseline dd733346281b672543cd4c205a352d2f8e3829fd.
This is support for the existing ticket; full boundary acceptance is NOT met.

## Implemented

RR SCORE/SCORE2 ordering now evaluates r>1 using the exact identity
z_r(x,y)=-z_(1/r)(y,x). It reuses freq_risk's constrained MLE and score.
This avoids overflowing r*r in the variance and incorrectly coalescing finite
scores to zero. No public API, score definition, ordering tolerance, nuisance
maximizer, NOSCORE profile or output golden changes. A regression covers
r=2,1e100,1e160,1e200,1e300 and positive rare tails bounded by 2/r at r=1e200.
The regression explicitly requests absolute tail accuracy 1e-213; a default
1e-10 bound is not sufficient to resolve a 1e-200 probability.

## Actual SAS 9.4 M9 oracle

Retained matrix.sas: ten exact interval procedures, zero errors/warnings.
Retained ordering.sas: eight FM score procedures, zero errors/warnings.
ordering.txt prints release 9.04.01M9P06052025. Raw listings are retained.
Run from a unique absolute dev2 path:

    /Users/thomas/sas/bin/sasrun /private/tmp/opensas-dev2-exact-boundary/matrix.sas -f text -o - -l /dev/null
    /Users/thomas/sas/bin/sasrun /private/tmp/opensas-dev2-exact-boundary/ordering.sas -f text -o - -l /dev/null

Actual captures used -o sibling.txt -l sibling.log. The initial matrix run
used the reserved macro name RUN and failed; only its corrected clean rerun
is evidence. The original batch-2 temporary probes are absent. Retained code
certificates and dev3's new README/interval evidence were read.

| Cells | Alpha | Method | SAS upper |
|---|---:|---|---:|
| [0,2;3,0] | .95 | SCORE and NOSCORE | .31043853759765 |
| [0,2;5,0] | .94 | SCORE and NOSCORE | .31875 |
| [0,2;5,0] | .99 | SCORE2 | .249913109375 |
| [0,3;5,0] | .99 | SCORE2 | .1666030883789 |
| [0,4;3,0] | .99 | SCORE2 | .11966864267985 |
| [0,2;3,0] | .05 | SCORE | 1.1139892578125 |
| [0,2;3,0] | .05 | SCORE2 | 1.00000038146972 |
| [0,2;3,0] | .8 | SCORE | .36754455566406 |

## New ordering evidence, remaining blocker

At r=.249913109375, n1=2,n2=5, SAS FM Z for x=0 and x=1,
y=5 is -.8163 and .8169. At r=.11966864267985, n1=4,n2=3,
SAS Z for x=0,1,2,3,y=3 is -.7374,.8031,2.3436,3.8841.
Those rankings agree with the kernel: the neighboring table is strictly MORE
extreme than the observed table. A tie tolerance change cannot explain these
SAS confidence endpoints. Constant-response x=n1,y=n2 suppresses the public
FM table; its score ordering is checked algebraically in the regression.

At p2=1 and r<1/(2*n1), every possible X has absolute score at least
that of X=0: |X/n1-r|>=r. Thus the SCORE2 tail is exactly one, including
at the three alpha=.99 SAS endpoints. The mathematical upper endpoints are
.25,1/6,.125; the SAS runtime differs by more than listing precision in two
of the three cases. This remains an unresolved SAS internal nuisance/search
compatibility issue, NOT a justified replacement of certified maximization.
For [0,2;5,0] at r=.31875, the directional supremum is .4641015625,
strictly below .94/2=.47; no nuisance maximizer alone can yield the target.
For [0,2;3,0], the .95 directional root is 1-sqrt(.475), not .3104385.
No endpoints were fitted or hardcoded, no case dropped or tolerance loosened.

SAS/STAT FREQ documentation specifies a supremum over all nuisance values,
with separate alpha/2 directional tails or one alpha SCORE2 tail. The retrieved
15.2 manual (PDF pp126–127,142–143) agrees with the retained formulas:
https://documentation.sas.com/api/docsets/statug/15.2/content/freq.pdf?locale=en
It does not specify the internal numerical search behavior needed for runtime
parity. Dev3 retains public EXACT/CL=EXACT integration; no API change is needed
for this numerical fix. Full ticket/SUPPORT readiness must not be inferred
from a green gate while these concrete discrepancies remain.
