# STAT-COMMON-011 verification

The unchanged original `unbalanced_sums_of_squares.sas` exits 0. All 96 listing
tokens match SAS exactly after whitespace splitting. No rows, labels, headings,
numeric fields, or probability tokens are omitted or relaxed. The original SAS,
expected listing, expected status, and reference log are unchanged. The saved
actual listing is complete, and the raw-token diff is empty.

## Semantics and implementation

SAS/STAT 15.4 physical p.286 defines containment: the continuous-variable
multisets must match, and the containing effect has a strict superset of CLASS
variables. Thus A*B contains A, but x*x does not contain x. Variable order does
not affect containment; continuous multiplicity does. GLM passes its actual
effect-factor metadata through `Options.type_ii`, one entry per effect.

For each target, the fitter excludes containing effects from the adjustment
model, places the target after the remaining effects, and computes the added
projection/rank. All tests retain the complete model's error DF and MSE. This
reuses the existing scaled QR, rank/alias policy, probability primitives and
fitted-value projection differences; it does not invert normal equations in
production or relabel Type III values. Numerical aliases remain frozen in the
complete model's retained space.

MODEL `/ SS2` prints only Type II. `/ SS1 SS2` prints both selected types. The
default remains I+III, and `/ SS1` retains its previous behavior. Parsed flags
are now `Spec.ss1` and `Spec.ss2` (the former replaces `ss1_only`).

Existing unsupported syntax stays explicit: mixed CLASS/continuous interaction
designs, higher-order/nested CLASS syntax, E2 symbolic display, and singular
numeric parameter displays are not enabled here. The numerical containment
primitive handles continuous/class metadata generally. Type II-only CLASS
models support empty-cell rank increments; unsupported singular graphs remain
guarded. No main/root or PRINT changes are included.

## Independent checks

The original main-effects oracle has no containing effects, so each target is
adjusted for both others. The verifier reads its DATALINES and independently
solves exact rational full/reduced normal equations, reusing COMMON010's
verification-only solver:

| Effect | DF | Exact Type II SS | Exact F |
|---|---:|---:|---:|
| group | 1 | 1243256/393825 | 1420864/502975 |
| x | 1 | 147175/1958 | 252300/3751 |
| z | 1 | 1323/1780 | 1134/1705 |

MSE is `2387/2136`, with 8 error DF. Both SAS and OpenSAS SS, MS, and F tokens
are checked against the rational reference within half their final decimal unit,
in addition to the strict full-listing token comparison.

Eight COMMON011 tests are registered through `glm_parse.zig`:

- For cell means `(13,10,19,17)` and sizes `(2,2,2,1)`, Table 16.7's independent
  `.6/.4` contrasts give Type II SS `(68.2666666667,11.2666666667,0.4)`;
  Type III gives `(67.6,10,0.4)`. Tests verify the full-model hypothesis rows
  `(0,2,0,.4)`, `(0,0,2,.4)`, `(0,0,0,4)`, estimates, covariance quadratic
  forms, SS/F, rank increments, and a closed-form F(1,3) survival probability.
- Balanced cells give `(84.5,12.5,.5)`, agreeing with Type III. Reordering the
  effects and CLASS declarations preserves Type II tests by effect identity.
- With A2B2 missing and other cell means `(2,6,10)`, Type II SS is `(64,16,0)`
  with DF `(1,1,0)`. Independent within-cell comparisons give hypothesis rows
  `(0,2,0,2)` and `(0,0,2,2)` orthogonal to the alias null vector.
- Orthogonal polynomial components verify that x and x*x adjust for one another.
  Exact and near-alias cases verify zero DF versus retained numerical rank.
- Separate FREQ/WEIGHT with NOINT matches explicit replication. A two-column
  CLASS effect verifies two numerator DF and the closed-form F(2,2) tail.
- Allocation-failure paths and malformed metadata are checked explicitly.

## Reproduction

```sh
zig build -j2
python3 tests/STAT15.4-oracle/STAT-COMMON-011/verify.py
zig build gate -j2 --summary all
```

The verifier preserves stdout, stderr, real exit status, raw token diff and JSON
under `.zig-cache/stat-common-011-evidence/`. The corpus includes the original
analysis. Final rebased SHA, full gate counts, and regression replays accompany
the delivery report. Sources read: this ticket's full entry, README, source,
expected output/status and log; S154 physical pp.285–289 and previously read
pp.123–134.
