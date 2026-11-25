# STAT-COMMON-012 verification

The unchanged original SAS program exits 0 and matches all **126 listing tokens**
exactly after whitespace splitting. No headers, observations, fields, effect rows,
or probabilities are omitted. Both requested tables are independently checked
against exact rational hypotheses. The SAS source, expected listing/status, and
reference log remain unchanged. Saved actual output is complete; the raw-token
diff is empty. Input hashes and references are in `verification.json`.

## Implemented scope

MODEL SS3 and SS4 select their corresponding tables; all combinations with SS1
and SS2 are supported, while the default remains I+III. Type IV results carry an
explicit checked basis, and the renderer rejects unvalidated Type IV results.

S154 physical pp.289–293 gives two sufficient equality cases: III=IV for effects
not contained in other effects, and for factorial models with no missing cells.
`glm_type34.zig` verifies one of these cases before sharing the existing Type III
hypothesis results with Type IV. It reuses the existing factor-containment rule,
sum-to-zero computational design, scaled QR, rank policy and effect tests.

For contained effects, the implementation checks the observed Cartesian product
of MODEL's CLASS factors after response/FREQ/WEIGHT filtering. It does not infer
completeness from matrix rank, N, or unfiltered source rows. Unused CLASS
declarations do not affect this check. Lower-order models without containing
effects can have estimable conditional tests despite absent joint cells.

General missing-cell orthogonal/distributive III/IV hypothesis construction is
**not implemented**. Such contained-effect patterns fail visibly, including a
full-rank three-factor case. Rank-deficient III/IV requests remain guarded, and
SS1/SS2 continue to work in their previously supported deficient cases. Existing
limitations on mixed/nested/higher-order CLASS syntax and symbolic E3/E4 displays
remain explicit. This change does not implement SOLUTION parameterization.

## Independent checks

The original main-effects model has no containing effects; exact rational
conditional SS are `1243256/393825`, `147175/1958`, `1323/1780`, with MSE
`2387/2136` and 8 error DF. `verify.py` checks SS, MS, and F in **both** III and IV
tables against these references within half their last printed decimal unit,
in addition to exact full-output token comparison. It reuses COMMON011's
verification-only rational solver, not production fit results.

Six registered tests additionally verify:

- Complete unbalanced 2x2 cell means `(13,10,19,17)`, counts `(2,2,2,1)`:
  equal-cell contrasts give III/IV SS `(67.6,10,.4)`. Tests check hypothesis
  orthogonality, `L*beta`, `L*G*L'`, rank/DF, F, and a closed-form F(1,3) tail.
- Balanced data give `(84.5,12.5,.5)`. Reversing observation order, CLASS order,
  effect order and level reference leaves the tests invariant by effect.
- A missing-corner additive model has estimable III/IV SS `(64,16)`; adding its
  interaction makes the unsupported III/IV request fail before table output.
  Combining SS4 with SS1 cannot bypass the guard.
- A three-factor model with seven of eight cells has full rank seven and N=14,
  yet is rejected for SS4. Raw rows with zero weight or zero frequency do not
  populate the missing cell. An unused third CLASS factor is ignored when
  validating the complete A*B model on the same data.
- A two-column CLASS effect gives numerator DF=2, SS=25.2 and F=6.3; its p-value
  agrees with the independent F(2,2) tail. Individual and combined table options
  produce exactly the requested tables. Unvalidated IV rendering fails visibly.
- Allocation failures release applicability and result storage.

The corpus includes the entire original analysis and a separate explicit
OpenSAS unsupported-pattern guard (expected status 2, empty stdout). The latter
is not presented as SAS's behavior for that supported SAS model.

## Reproduction

```sh
zig build -j2
python3 tests/STAT15.4-oracle/STAT-COMMON-012/verify.py
zig build gate -j2 --summary all
```

Raw stdout/stderr, status, diff and verification JSON are retained under
`.zig-cache/stat-common-012-evidence/`. Final exact-SHA gate counts accompany
the delivery report. Sources read: this ticket and every listed oracle file,
S154 physical pp.289–293, and previously read pp.123–134.
