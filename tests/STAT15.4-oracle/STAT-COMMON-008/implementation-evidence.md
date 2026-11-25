# STAT-COMMON-008 REF/EFFECT implementation evidence

## Sources and bounded implementation

Read the [README](README.md), [unchanged original program](reference_effect_coding.sas), [complete expected listing](reference_effect_coding.expected.txt), [expected status](reference_effect_coding.expected.rc), and [SAS log](reference_effect_coding.oracle.log). Manual sources: S154 Chapter 20 **physical pp.418–421**; Chapter 79 CLASS/REF/PARAM on **5851–5854**, MODEL/EVENT on **5870–5871**, missing values/response ordering on **5905**, scoring and convergence on **5909–5912**, fit criteria/global tests on **5914–5918**, parameter/odds inference on **5920,5922,5937**, and displayed output on **5962–5966**. The primary checkout's PDF was used.

New modules separate [coding/design](../../../src/stat/logistic_design.zig), [binary fitting](../../../src/stat/logistic_fit.zig), and [LOGISTIC parsing/display](../../../src/stat/logistic.zig). Main/root changes only expose the procedure and dispatch its listing. Existing GLM inference and PRINT functions are unchanged.

Supported path: single-trial binary logit, intercept, continuous and categorical main effects, explicit/default EVENT, CLASS REF=FIRST/LAST/formatted level, PARAM=REF/REFERENCE or EFFECT (global or per variable), FORMAT, existing DATA/WHERE selection, NOPRINT, and explicit LINK=LOGIT. Default CLASS coding is EFFECT, reference is LAST, and modeled response is the first ordered level. Typed/formatted levels come from `class_levels`; unformatted numeric references use raw values rather than rounded display labels.

This implements only the required binary subset of existing LOGISTIC-001/002/003/004/005 prerequisites. Those broader tickets are not claimed complete. Ordinal/multinomial responses, other parameterizations, interactions/nesting, BY/FREQ/WEIGHT/STRATA, model selection, alternate links, Firth/exact methods, output datasets, and graphics are not silently mapped to this method. Singular/separated/nonconvergent fits emit a visible gap without a fabricated coefficient table. CLASS levels lost through complete-case exclusion are also guarded rather than silently changing the parameterization.

## Algorithm and statistical output

Fisher scoring uses the existing scaled-QR least-squares core for weighted steps and the inverse information matrix. Stable sigmoid/softplus formulas evaluate probabilities, gradients, and likelihood; step halving prevents a likelihood-decreasing update. The published default GCONV=1E-8 controls stopping. Complete separation and a standardized covariance check for quasi-separation cause a visible failure. This is a general matrix solver; it contains no dataset names, fixture signatures, or fitted-value constants.

The current information inverse supplies standard errors. Likelihood-ratio, null score, global Wald, and per-effect joint Wald tests are computed from their definitions. REF/EFFECT odds ratios use the **difference between level coding vectors**, so EFFECT coding does not incorrectly exponentiate just one coefficient. Wald limits use a normal quantile. Binary association counts actual event/nonevent pairs and derives all displayed indices.

Stopping at SAS's documented GCONV criterion matters: the original data meet it before the more precise likelihood maximum. The implementation does not oversolve then adjust values to the fixture. Independent analytic tests can request a tighter criterion through the numeric API without changing the production default.

## Original oracle and regression acceptance

The real CLI executed the complete original `.sas` file, including DATA steps and both LOGISTIC analyses. All **430 expected tokens** matched exactly after whitespace-only normalization; actual/reference status was **0/0** and stderr was **empty**. No original program, expected result, or reference log was changed.

The comparison includes both parameterizations' model information, response profiles, explicit event, 0/1 versus -1/1 design values, convergence status, both fit-statistic columns, all three global tests, Type 3 tests, every coefficient/SE/Wald/p-value, both odds ratios and their limits, and every association measure. It excludes no rows or digits and applies no numeric tolerance to the oracle listing.

The unchanged COMMON-007 and COMMON-006 original programs also pass with **261** and **228** matching tokens respectively, exit 0, and empty stderr.

## Independent and invariance checks

Eight inline tests pass (nine focused runner tests including the root):

- Intercept-only sample with one event out of four: coefficient `log(1/3)` and variance `4/3`.
- Two groups of five, with two and three events: coefficients `log(2/3)` and `log(2.25)`, intercept variance `5/6`, slope variance `5/3`. These are independent binomial-logit identities.
- Chi-square(2) survival at 20 equals `exp(-10)`, independently checking the tail function.
- All cells of the manual four-level REF/EFFECT coding matrices are checked exactly.
- Original-case REF/EFFECT predictions and likelihood agree; the coefficient/covariance transformation and contrast-based odds ratios agree on their unrounded values.
- Changing the reference preserves predictions and reciprocates the appropriate OR. Changing the modeled event complements predictions and reverses coefficient signs.
- Four groups of four with event counts (1,2,3,2): fitted probabilities equal (.25,.5,.75,.5), and three-column EFFECT contrasts give the same ORs as REF coding (3,9,3).
- Singular matrices, complete separation, invalid responses/references, and unsupported coding are rejected; captured diagnostics and no-output behavior are checked.

Analytic/inter-parameterization checks use fixed absolute tolerances from `1e-13` to `1e-9`, according to iterative convergence and QR/contrast arithmetic. Analytic fits use GCONV=1e-20 where needed. None of these tolerances is derived from a discrepancy in the SAS fixture; the original listing comparison remains exact-token equality.

## Reproduction and final gate

From the repository root:

```sh
/Users/thomas/.local/share/zig-0.16.0/zig build -j2
python3 - <<'PY'
from pathlib import Path
import subprocess
cases = [('STAT-COMMON-008','reference_effect_coding'),
         ('STAT-COMMON-007','effect_design'),
         ('STAT-COMMON-006','class_order')]
for ticket, case in cases:
    base = Path('tests/STAT15.4-oracle') / ticket / case
    r = subprocess.run(['zig-out/bin/opensas', str(base)+'.sas'], text=True, capture_output=True)
    expected = Path(str(base)+'.expected.txt').read_text().split()
    assert r.returncode == int(Path(str(base)+'.expected.rc').read_text()) == 0
    assert r.stderr == '', (ticket, r.stderr)
    assert r.stdout.split() == expected, ticket
    print(ticket, len(expected), 'tokens: PASS')
PY
/Users/thomas/.local/share/zig-0.16.0/zig build gate -j2 --summary all
```

The numeric and procedure tests are imported in the real graph. The final handoff records exact commit/base, direct gate subprocess exit, full test count, corpus/program counts, and a verified failure-free log. A fresh task-specific `--cache-dir` is used when a previously removed cached build runner causes FileNotFound; no cache deletion or masked pipeline exit is used.
