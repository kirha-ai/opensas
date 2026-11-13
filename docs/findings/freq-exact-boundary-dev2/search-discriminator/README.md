# Bounded exact RR search discriminator (SUPPORT, not ticket completion)

Branch baseline: 9ed9c58f1efee9df230f0c12e79d566c814fe020.
No certified core or compatibility-layer changes. This evidence-only diagnostic
ends here: no candidate reproduced generic SAS behavior on held-out inputs.

## Reproduce

Run `python3 discriminator.py` in this directory. It uses only Python's standard
library, reads the retained SAS logs, verifies extraction counts/controls/swaps,
and regenerates paths.csv and predictions.csv. It does NOT import opensas or
use SAS endpoint values inside any numerical candidate. generate_heldout.py
regenerates heldout.sas from the fixed candidate-test manifest in discriminator.py.
To rerun an oracle, first copy the SAS source to a unique absolute dev2 temp path,
then use `/Users/thomas/sas/bin/sasrun absolute.sas -f text -o - -l /dev/null`.
Captured runs used sibling .txt/.log destinations. Empty text outputs are normal
for ODS-excluded runs; the tagged numeric records are in .log.

Retained sources/results:
- sweep.sas/.log/.txt: 192 procedures, zero errors/warnings; 768 limit records.
- confirm.sas/.log/.txt: 36 procedures, zero errors/warnings; 144 limit records.
- heldout.sas/.log/.txt: 18 NEW procedures, zero errors/warnings; 18 upper limits.
- search-controls-report.md: prior control/swap/sweep findings, preserved.
- paths.csv: every candidate bisection iterate, exact rational tail maximum,
  nuisance estimate, computed probability, residual, branch/stop action.
- predictions.csv: 4 training and 18 held-out SAS intervals versus 5 candidates.

MAXTIME1/60 comparisons (96 limits) and physical swaps/repeats (144 limits)
are asserted equal to corresponding defaults. Exactly125 distinct shape/null
SCORE event sets are enumerated with independent70-digit Decimal constrained
MLEs; each is the single opposing-zero table. Thus the closed polynomial used
by the candidate comparisons is valid for SCORE as well as NOSCORE here.

## Fixed candidates and independent mathematics

For [0,n1;n2,0], this directional tail is
`f(q)=(1-r*q)^n1*q^n2`, on `0<=q<=min(1,1/r)`.
Its log is concave and its global maximum is at
`q=min(1,1/r,n2/(r*(n1+n2)))`. Exact Fraction arithmetic evaluates the
maximum at every recorded outer midpoint, independently of floating optimizers.

Candidates fixed BEFORE the held-out oracle:
1. Analytic maximum.
2. Golden-section search, reset bracket,64 iterations, endpoints checked.
3. Safeguarded projected Newton on log(f), reset at half the legal range.
4. Same Newton search, warm-started from the preceding nuisance estimate.
5. Golden-section search,64 iterations, WITHOUT explicit endpoint evaluation.

Each uses the retained outer-profile hypothesis: modified point seed,
upper seed twice that point (ordinary Wald is undefined here), bracket doubling,
bisection, first rejected p within1e-6 of alpha/2. No fitted parameters or
endpoint constants enter these algorithms. This tests a specific hypothesis;
it is not a claim about SAS's undocumented implementation.

## Training transition: alpha .939/.940, n1=2,n2=5

The first eight branch decisions are identical for both targets. The first
five midpoints are3/10,7/20,13/40,5/16,51/160. At51/160=.31875:

- exact nuisance maximum:11881/25600=.4641015625, attained at q=1;
- residual versus .939/2: -.0053984375;
- residual versus .940/2: -.0058984375;
- all five candidates reject and CONTINUE for both alphas.

Their first different branch occurs at iteration9, r=161/512.
All candidates eventually predict .31479949951171876 at alpha .939 and
.314434814453125 at alpha .940. SAS gives .31479949951171 and .31875.
The latter equals the fifth candidate midpoint; endpoint output alone does
NOT prove that SAS actually stopped at iteration5.

Warm/reset starts cannot explain a p near .47 at r=.31875: no LEGAL q yields
more than .4641015625. Also, a uniform absolute-residual rule that stopped the
shared fifth midpoint for .940 would stop it for .939, whose residual is smaller.
An alpha-independent width/iteration stop has the same problem along the shared
path. These are precise rejections of these candidates, not exclusions of inputs.

## Held-out predictions

Fixed held-out shapes/alphas:
- [0,3;4,0]: .939,.940,.941;
- [0,5;2,0]: .949,.950,.951;
- [0,2;7,0]: .937,.940,.943.
Both SCORE and NOSCORE,18 intervals. All five candidates match only1/18 within
absolute .00005 listing precision (2/4 training intervals); maximum held-out
error is .005408477783203081. This comparison threshold is for classifying
oracle agreement only, not a change to production or certified tolerances.

Examples:
| Shape | Alpha | Method | SAS upper | Candidate upper |
|---|---:|---|---:|---:|
| [0,3;4,0] | .940 | NOSCORE | .22054290771484 | .2225020272391183 |
| [0,3;4,0] | .940 | SCORE | .22211519677734 | .2225020272391183 |
| [0,5;2,0] | .950 | both | .13783298839222 | .13833479447798294 |
| [0,2;7,0] | .943 | both | .31875 | .3133415222167969 |

## Exact unresolved decision

No tested reset/warm nuisance optimizer plus the established ordinary outer
p-stop predicts the high-alpha runtime outputs. The same singleton objective
can produce different SAS SCORE/NOSCORE endpoints, although its exact probability
and ordering coincide. To implement a generic compatibility layer, we still need
to identify how SAS's method/target-dependent internal search state or termination
status selects a returned endpoint: specifically whether the discrepancy enters
through target-dependent nuisance stopping/status, or outer-bracket update and
termination handling. Endpoint observations do not distinguish those mechanisms.
No algorithm was selected or production change made on speculation. The bounded
discriminator is inconclusive for full compatibility; FEAT-freq-exact remains
DOING. The existing certified core and previously green overflow fix stay intact.
