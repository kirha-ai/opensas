# Exact RR default-search diagnostic — dev2, 2026-11-13

No repository files changed. Branch dev2, HEAD/base
9ed9c58f1efee9df230f0c12e79d566c814fe020. Full ticket remains DOING.

## Documented controls

SAS/STAT 15.2 FREQ manual, EXACT statement PDF pages23,26–27:
https://documentation.sas.com/api/docsets/statug/15.2/content/freq.pdf?locale=en
RELRISK has COLUMN and METHOD. Global EXACT computation options are ALPHA,
MAXTIME, MC, MIDP, N, PFORMAT, POINT, SEED. ALPHA/N/SEED control MC, which
is not used for RELRISK; MIDP/POINT are unavailable for RELRISK. PFORMAT
controls display of p-values. MAXTIME is a resource deadline, not accuracy.
No EXACT RR CONVERGE, EPSILON or GRID/search-precision control is documented.
CONVERGE/MAXITER apply to PLCORR. No invalid controls were submitted.

## Runs and extraction

sweep.sas: 192 procedures, 0 errors/0 warnings, SAS elapsed35.797s.
confirm.sas: 36 procedures, 0 errors/0 warnings, elapsed8.453s.
Both run with /Users/thomas/sas/bin/sasrun absolute.sas -f text -o sibling.txt
-l sibling.log. Each procedure has uniquely named ODS datasets. Metadata and
BEST32 endpoint values are emitted as RESULT/CHECK lines in the logs.
Expected extraction counts asserted: 768 sweep limits, 144 confirmation limits.
SAS 9.04.01M9P06052025 was independently printed in prior ordering.sas.

Sweep covers [0,2;3,0], [0,2;5,0], [0,4;3,0], three methods, neighboring
alpha values, both columns, original/reversed rows. MAXTIME1 and60 are
compared against defaults for four discriminating shape/alpha combinations,
all methods and both columns: 24 procedures/96 limits identical to default.

Confirmation physically swaps columns, both rows and columns, or repeats
the original table, for four shape/alpha combinations and three methods.
All144 corresponding endpoint values are EXACTLY equal after column remapping.
This rules out a COLUMN=2 adapter issue and confirms reproducible results across
independent procedures/runs in these cases.

## Nonmonotone output and residuals

For [0,2;5,0], NOSCORE and SCORE:
alpha .939: upper .31479949951171
alpha .940: upper .31875
alpha .941: upper .31875
The upper confidence bound increases despite higher alpha. At .31875 the
true directional supremum is (1-r)^2=.4641015625, versus target .47 or.4705.
Thus ordinary output rounding or an approximately1e-6 probability-stop cannot
explain the discrepancy.

For [0,4;3,0], SCORE2:
alpha .989: upper .11974875132242
alpha .990: upper .11966864267985
alpha .991: upper .12476445486111
alpha .999: upper .12476445486111
Each is below1/8 and has certified two-sided tail exactly1. The sudden upward
jump at .991 also contradicts a fixed-tail inversion with monotone acceptance.

For [0,2;3,0], NOSCORE/SCORE:
alpha .949 and.950 both return .31043853759765; true tail .47549501043047
exceeds the respective .4745/.475 targets by .00099501043047/.00049501043047.
alpha .951 returns .31043548583983 with residual about-7.80811e-7.
This is a plateau followed by ordinary fine root search, not uniform rounding.

## Orientation

Across all28 shape/alpha points, NOSCORE upper vs reciprocal reversed-row lower
agrees within1.04e-14 (BEST32 transcription). SCORE and SCORE2 do not:
[0,2;5,0],alpha .941,SCORE: upper .31875, reciprocal reversed lower
.3140563343581484 (difference .004693665641851585).
[0,4;3,0],alpha .99,SCORE2: upper .11966864267985, reciprocal reversed lower
.12500000325962915 (difference .005331360579779149).
Physical column swaps preserve these values, so this concerns orientation of
the numerical interval search, not formatting/column selection.

## Conclusion and next discriminator

Evidence establishes deterministic, method/orientation-dependent default
numerical behavior. It does NOT identify a documented approximation algorithm
or a generic implementation that predicts the anomalous endpoints. No fitted
endpoint constants, tolerance relaxation, exclusions or core changes were made.
An explicit compatibility layer is architecturally possible, but not justified
by a validated solver yet. Simple fixed-nuisance clipping, fixed probability
stopping error, listing rounding, deadline truncation and reciprocal score
search equivalence do not explain this matrix.

A useful next bounded discriminator would trace assumed outer bisection paths
against independent tail values, particularly the .939/.940 transition, and
compare candidate nuisance maximizers with warm starts/reset starts. That is
further algorithm identification, not a claim that such a solver is established.

Last actual code verification remains the landed9ed9c58 gate:
1213/1213 tests,2049/2049 corpus,11/11 programs. No code changed in this diagnostic.
