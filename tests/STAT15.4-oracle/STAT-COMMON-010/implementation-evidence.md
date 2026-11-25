# STAT-COMMON-010 verification

The unchanged `unbalanced_sums_of_squares.sas` exits 0. All 96 expected
listing tokens match exactly after whitespace splitting: no omitted titles,
headings, rows, numeric fields, probabilities, or tables. The reference SAS
source, expected listing, expected status, and log remain unchanged.
`unbalanced_sums_of_squares.actual.txt` preserves the complete OpenSAS listing;
the raw-token diff is empty. `verification.json` records the immutable input
hashes and exact-rational references.

## Implementation

MODEL `/ SS1` requests only the Type I effect table. Without that option GLM
continues to print both Type I and Type III. The fit remains the shared ordered
rank-policy/QR implementation; no new least-squares solver was introduced.
Every sequential test uses the full model's error DF and MSE.

Type I-only CLASS models can use their actual rank increments even with empty
cells. The default missing-cell Type III guard remains. Singular numeric-only
parameter displays, singular graphics, E1 symbolic display, and other SS types
are not enabled by this change. Singular CLASS models require PLOTS=NONE if
graphics are enabled; their Type I tables remain available.

`glm_ss1_tests.zig` is registered through `glm_parse.zig`, with no main/root
changes. Existing `glm_fit.zig` tests continue covering exact aliases and near
rank decisions. A corpus fixture reproduces the entire COMMON010 analysis.

## Independent calculations

`verify.py` reads the original DATALINES and computes successive intercept,
group, x, and z fits using exact rational normal equations (verification only).
It checks the displayed SS, MS, and F in both SAS and OpenSAS against these
references, within half the last displayed decimal unit:

| Effect | DF | Exact Type I SS | Exact F |
|---|---:|---:|---:|
| group | 1 | 5929/12 | 13706/31 |
| x | 1 | 2023/20 | 154326/1705 |
| z | 1 | 1323/1780 | 1134/1705 |

Full-model MSE is `2387/2136`, with 8 residual DF. The unused input variables
named weight and freq do not affect the analysis.

The independent empty-cell example has three observed cells with means
`(2,6,10)`, each based on two observations with residuals -1 and +1. A2B2 is
absent. For model order A, B, A*B, sequential SS are `(48,16,0)` with DF
`(1,1,0)`, full rank 3, SSE 6, and MSE 2. Reversing A and B gives `(0,64,0)`.
Both decompose model SS 64. Filling the fourth cell with mean 14 gives balanced
SS `(128,32,0)` and reordered SS `(32,128,0)`.

For the empty-cell sum-contrast design `[Intercept,A,B,A*B]`, the test derives
the independent Type I hypothesis rows `(0,2,-1,1)` and `(0,0,2,2)` as U'X.
It checks their orthogonality to the alias null vector `(1,-1,-1,1)`, the
identities `L*beta = U'y` and `L*G*L' = U'U`, the associated projections'
idempotence and trace, and SS/F against those constructions. This directly
tests that earlier Type I hypotheses can include later model parameters.

## Reproduction

```sh
zig build -j2
python3 tests/STAT15.4-oracle/STAT-COMMON-010/verify.py
zig build gate -j2 --summary all
```

The verifier preserves stdout, stderr, real exit status, token diff, and JSON
under `.zig-cache/stat-common-010-evidence/`. It fails on any token difference
or nonzero status. Final gate counts and the tested SHA accompany the delivery
report. The original GLM002 program was also replayed: all 671 listing tokens,
three graphs, and exit status 0 remain intact.

Sources read: SAS/STAT 15.4 physical pp.284–285 and 123–134, plus this ticket's
README, complete SAS source, expected output, and reference log.
