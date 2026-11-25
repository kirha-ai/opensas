# STAT-REG-004 interactive execution

## Source and original replay

Read this ticket's README, original SAS program, expected listing, rc, diagnostic
fixture and complete reference log, plus SAS/STAT 15.4 physical pages 8574–8576,
8592–8593 and 8610–8613. The original case contains ADD/PRINT, but not DELETE or
REFIT. Its own unchanged source was executed independently before and after the
change; the matching filename in other tickets was not used as proof.

The two Population Output Statistics residual sums have the exact same unrestricted,
unweighted intercept-model identity verified from this source. The existing
REG-002 verifier recomputes exact Fraction coefficients and the two scale budgets
from this file. Only those two quantities use tolerant acceptance. All other
1,116 output tokens, status 1 and the two required warnings compare exactly.
Strict whitespace equality is false and is disclosed in `numeric-verification.json`.

```sh
python3 tests/STAT15.4-oracle/STAT-REG-002/verify_numeric_contract.py \
  --oracle-dir tests/STAT15.4-oracle/STAT-REG-004 --case documented_feature \
  --report tests/STAT15.4-oracle/STAT-REG-004/numeric-verification.json
zig build gate -j2 --summary all
```

## Implemented semantics

- ADD and DELETE modify the current (last) MODEL statement, including all its
  responses, rather than earlier MODEL statements. A parser statement identifier
  keeps the group explicit. Revision suffixes count successful ADD/DELETE actions.
- Both operations recompute the model immediately. Validation and fitting finish
  before committing the candidate model/fit, so an invalid mixed ADD list cannot
  partially change the model or emit a false added-variable note.
- The first-RUN variable pool and its missing-value exclusions remain fixed even
  when regressors are deleted. ADD cannot introduce a variable absent from that pool.
- REFIT invokes the same validated computation as normal execution, stores current
  fits, and emits neither a listing nor an output dataset. A failed refit preserves
  the last valid fit and reports its computational error.
- Plain PRINT refits and emits the current model at its own statement position.
  `PRINT; DELETE x; PRINT; RUN;` therefore emits both results in order. Previously
  a deferred boolean lost the first result.
- RUN preserves the session; QUIT ends it. The CLI's isolated REG continuation
  guard uses the module's admission list for DELETE, REFIT and documented commands
  that must reach fail-loud gap diagnostics.

The shared fit was factored without changing the solver, frequency/weight rules or
covariance rescaling. No expected fixture was modified. The renderer is unchanged.

## Independent and source-example checks

`src/stat/reg_interactive_tests.zig` runs through the actual session and fitter.
Four corners x,z = (-1,-1), (-1,1), (1,-1), (1,1) generate

    y = 10 + 2*x - 3*z + x*z
    v = -4 + x/2 + 5*z + 2*x*z.

A fifth observation has missing z and must stay excluded throughout deletion and
restoration. Orthogonality of 1,x,z,x*z gives the following independent results:

| State | y coefficients | SSE | Error DF | F | F tail |
|---|---|---:|---:|---:|---|
| Initial x,z | (10,2,-3) | 4 | 1 | 6.5 | 1/sqrt(14) |
| DELETE z | (10,2) | 40 | 2 | .8 | 1-sqrt(2/7) |
| DELETE x | (10) | 56 | 3 | missing | missing |
| ADD z x | (10,-3,2) | 4 | 1 | 6.5 | 1/sqrt(14) |

Coefficients/SSE/DF are exact dyadic checks. F probabilities use independently
derived closed forms with a 32-machine-epsilon numerical assertion. The same valid
program was run through the real CLI: rc 0, exactly four ordered listings, five
observations read/four used for every fit, and no REFIT listing. Its complete source,
observed result records and stderr are in `interactive-verification.json`.

Additional checks cover both responses of the last MODEL, no leakage of earlier
MODEL results, an undeclared ADD variable (captured status 1, unchanged state), a
computational REFIT failure instead of a silent no-op, malformed REFIT/DELETE,
unknown PRINT/statement names, and named unsupported extensions. REFIT also preserves
an existing OUTEST dataset object, testing its no-output behavior directly.

The manual's separate source example (physical pp.8610–8611) was also run: initial
Weight=Age Height followed by DELETE Age, REFIT, PRINT. Six full-model coefficient/SS/MS fields
match Figure 105.26 at their documented precision. The entire reduced-model table matches the supplied
CLASS Weight=Height reference, with MODEL1.1 as documented after DELETE. No numeric
tolerance was used for that reduced table; source and results are recorded separately.

The existing CLI regression now enters REFIT and DELETE as first statements of
new chunks and checks the new model label and subsequent DATA-step execution.

## Explicit boundaries

This change supports plain PRINT and its inherited MODEL output settings. Named
PRINT options (including ANOVA/MODELDATA), other interactive extensions such as
REWEIGHT/PAINT, interactive OUTEST across multiple distinct MODEL statements,
DELETE of an inactive variable, and deletion of every NOINT parameter remain
explicit gap errors (rc 2), not ignored operations. Typos and malformed syntax are
user errors (rc 1). An intercept-only model is supported and tested, with undefined
model F statistics represented as missing. No broad claim about unexercised PRINT
options or reweighting is made.
