# STAT-GLM-004 parameterization evidence

No production behavior changes are needed for the supplied case. This task adds
independent tests and a ticket-specific original-case verifier. The parser,
renderer, numerical kernels, main/root dispatch and expected output are unchanged.
The landed COMMON007 `design_matrix.zig` API is reused; no coded-design generator
is duplicated.

## Source and scope

Read the complete ticket, README, original SAS, expected listing and reference
log, and SAS/STAT 15.4 User's Guide physical pages **4110–4115**, printed pages
**4098–4103**. Page indexing was checked as `PdfReader.pages[physical - 1]` and
against each printed running header.

- Physical 4110 specifies the intercept, copied continuous columns and multiplied
  polynomial terms.
- Physical 4111 specifies one indicator column per CLASS level and each observed
  crossed combination, with the rightmost CLASS factor varying fastest.
- Physical 4112–4113 describe nested and continuous-by-class column structure.
- Physical 4114 explains the overparameterized model, generalized g2 inverse,
  and zero solution entries for columns dependent on previous columns.
- Physical 4115 introduces hypothesis tests on estimable functions.

The current GLM inference path uses a computational contrast basis for its
validated complete hierarchical models. Tests prove its model-space and estimable
hypothesis equivalence; they do **not** claim those contrast columns are the public
full GLM SOLUTION parameterization. Full coded-design generation is COMMON007.
Unsupported GLM SOLUTION/nesting/missing-cell hypotheses retain the existing
explicit guards; this work does not advertise additional syntax or hypothesis
support. Existing GLM003 tests continue to check those guards and missing inputs.

## Independent basis tests

`src/stat/glm_parameterization_tests.zig` is imported by the existing GLM test
module, so its tests run in the normal gate.

1. **Documented full indicator basis versus computational contrasts.** For the
   original unbalanced 2×2 data, the reference full columns are
   `I,A1,A2,B1,B2,A1B1,A1B2,A2B1,A2B2`. Four literal indicator rows are expanded
   only as test data. Exact dyadic transformations recover all nine columns from
   the four contrast columns and recover all four contrasts from the full rows.
   The real COMMON007 builder must match every literal cell, nine column names,
   class-membership mapping, row count and source-row index.

   Both bases have rank 4 and error DF 3, with SSE=6 and fitted cell means
   13,10,19,17. The ordered full g2 solution is `(17,-7,0,2,0,1,0,0,0)`; all
   aliased coefficients are exactly zero and their displayed SEs are missing.
   Estimable cell-mean variances are 1 for replicated cells and 2 for the
   singleton cell, in both bases (MSE=2 divided by cell count).

   Explicit full-basis L vectors test the equal-cell A and B marginal differences
   and interaction difference-of-differences. Their estimates are -6.5,2.5,1;
   unscaled variances are 5/8,5/8,5/2. Hence SS=(338/5,10,2/5), independently
   agreeing with the contrast-path Type III tests. Redundant full dummy blocks
   are not incorrectly deleted to define those hypotheses.

2. **Reference ordering.** DATA order beginning with A2/B2 versus INTERNAL order
   beginning with A1/B1 transforms the contrast basis by diag(1,-1,-1,1).
   Every row is checked exactly; coefficient and covariance sign transformations
   and fitted-value invariance are then checked. This is ORDER/reference-position
   verification, not a claim that currently unsupported CLASS REF= syntax exists.

3. **Polynomial change of origin.** For x=0,1,2,3 and t=x-3/2, the raw and centered
   quadratic matrices obey an exact triangular transformation. Responses are
   `(1,4,9,16)+(-1,3,-3,1)/8`; the residual vector is exactly orthogonal to
   1,x,x². Independent targets are beta_raw=(1,2,1), beta_centered=(25/4,5,1),
   SSE=5/16, residual DF=1 and fitted values (1,4,9,16). Raw covariance is

   ```
   [[19,-21,5],[-21,49,-15],[5,-15,5]] / 64.
   ```

   The test verifies this exact rational covariance and its centered-basis
   transformation, not merely agreement between two calls to the same fitter.

All reference matrices and basis transformations use exact binary-representable
integers/halves/quarters. Numeric fitting comparisons use
`condition * gamma(32*n*p*p) * max(1,abs(reference))`, with binary64 unit roundoff
u=2^-53 and gamma(k)=k*u/(1-k*u). The retained full factorial normal matrix has
infinity norm 17 and inverse norm 13/2, giving condition 221/2. The raw quadratic
normal matrix has norm 148 and inverse norm 17/4, giving condition 629. These are
conservative conditioning bounds for both compared bases, fixed independently of
observed errors. Original listing comparison uses zero numerical tolerance.

## Original case and graphics

The original GLM004 SAS program executes unchanged. The baseline independently
passed expected/actual status 0/0 and all **671/671** listing tokens, using only
whitespace tokenization. It includes five analyses: two factorial, two quadratic,
and one linear. Default Type I + Type III output is retained.

Three real SVGs are required: IntPlot with seven observations/two groups,
SGSCATTER with thirteen observations, and FitPlot with thirteen observations plus
101 fitted points and ordered finite confidence/prediction bounds. The verifier
checks complete stdout, exact exit status, every stderr line, graph count and
structural point data. Only the three native SVG-publication notes are permitted.
Historical SAS session/source-echo notes and PNG paths are not asserted identical
to native SVG diagnostics.

Reproduce from the repository root:

```
zig build gate -j2 --summary all
zig build -j2
python3 tests/STAT15.4-oracle/STAT-GLM-004/verify.py
```

The ticket-specific verifier reuses the existing strict contract but runs only
GLM004 with its own expected file. Full stdout/stderr, token diff, expected hash,
OpenSAS identity, and graph inventory are retained under
`.zig-cache/stat-glm-004-evidence/verified/`. Final rebased SHA/base, direct gate
exit and counts are recorded in the delivery report. No expected-output, board,
shared production-source changes or pushes are made by dev2 for this task.
