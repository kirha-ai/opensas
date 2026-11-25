# STAT-REG-003 MODEL verification

The ticket's original `documented_feature.sas`, expected listing, diagnostic
fixture, return code and reference log were read and executed independently.
The README identifies one case. The supplied manual was read at physical
pp.8576–8588 (printed pp.8564–8576).

## Applicable MODEL semantics

Physical p.8576 requires numeric dependent and regressor variables, allows an
optional model label and multiple dependents, and explicitly disallows writing
`X1*X1` in MODEL. Polynomial variables must first be constructed in a DATA step.
Physical p.8583 documents the implicit intercept and its suppression by NOINT.
Therefore CLASS reference levels, categorical coding, missing categorical levels
and GLM-style inline interactions are not inferred for REG. The broader COMMON-007
design dependency is not needed to execute this numeric-column model path.

The original source uses:

- SASHELP.CLASS: `Weight=Height`, 19 observations and design columns (1, Height).
- USPopulation: 22 observations, Year=1790 through 2000 in increments of 10,
  Population divided by 1000, and a precomputed `YearSq=Year*Year`.
- Initial Population MODEL: design (1, Year), with R CLM CLI output.
- ADD YearSq / PRINT / RUN: design (1, Year, YearSq), label MODEL1.1.
- A new final MODEL explicitly names Year and YearSq again.

No categorical or implicit-effect implementation is claimed. Advanced MODEL
selection, covariance and influence options are not inferred from this example.

## Direct design and semantic regression

`src/stat/reg_model_tests.zig` is registered in the root test block. It deliberately
stores columns in descriptor order (z, response_b, x, response_a) while MODEL
names regressors in order (x,z). Four observations are the corners
(-1,-1), (-1,1), (1,-1), (1,1). The independent columns 1,x,z,x*z are mutually
orthogonal and have squared norm 4.

    response_a = 10 + 2*x - 3*z + x*z
    response_b = -4 + x/2 + 5*z + 2*x*z

The test parses two labeled MODEL statements, the first with two responses and
the second with NOINT. It checks the resolved response/predictor indices, labels,
intercept flags, actual selected X/y arrays, and resulting numerical fits:

| Model | Coefficients | SSE | Error DF |
|---|---|---:|---:|
| response_a, intercept | (10,2,-3) | 4 | 1 |
| response_b, intercept | (-4,0.5,5) | 16 | 1 |
| response_a, NOINT | (2,-3) | 404 | 2 |

These small dyadic calculations use exact comparisons. This is not a parser-only
success check. A separate captured-diagnostics test rejects a character regressor
with status 1 and no listing, rather than silently constructing CLASS effects.
Existing regressions independently cover invalid character responses, invalid
inline `x*x`, missing '=', invalid options, shared missingness across MODEL/VAR,
and default model numbering per statement rather than per dependent variable.

## Complete original-oracle comparison

`numeric-verification.json` records the original program hash, unchanged expected
hash, actual binary version, actual/expected rc, full emitted stderr, all token
counts, exact rational coefficients and bounds, and seven rejection controls.
The run uses the existing REG-002 verifier, selecting this ticket explicitly:

```sh
python3 tests/STAT15.4-oracle/STAT-REG-002/verify_numeric_contract.py \
  --oracle-dir tests/STAT15.4-oracle/STAT-REG-003 --case documented_feature \
  --report tests/STAT15.4-oracle/STAT-REG-003/numeric-verification.json
zig build gate -j2 --summary all
```

This source independently supplies the same unrestricted, unweighted intercept
models and the same two Population Output Statistics residual-sum fields. The
bounds are recomputed from this source with exact Fraction arithmetic; neither
another ticket's receipt nor its observed tails are used as inputs. The explicit
model/dependent/field-position checks remain unchanged.

Only those two sums use the already documented contract in
`../STAT-REG-002/numeric-contract.md`: bounds 7.261130843592319e-11 (linear) and
1.7845359484002278e-9 (quadratic), independently around analytic zero for both SAS
and OpenSAS. All other 1,116 tokens compare exactly after whitespace normalization.
Expected status is 1 and both required warnings compare exactly. Additional
emitted NOTE messages must occur in this case's own supplied reference log.
Strict whitespace equality is false, and tolerant acceptance is disclosed.
No source program, expected fixture, production REG parser, execution module,
renderer, fitter, or board is changed by this verification work.
