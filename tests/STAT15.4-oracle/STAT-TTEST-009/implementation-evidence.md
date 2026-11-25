# STAT-TTEST-009 implementation evidence

## Sources and scope

Read the [fixture README](README.md), [original program](tost_difference.sas), [complete expected listing](tost_difference.expected.txt), [expected status](tost_difference.expected.rc), and [SAS reference log](tost_difference.oracle.log). The [SAS/STAT 15.4 User's Guide](../../../docs/SAS-STAT-15.4-Users-Guide.pdf), Chapter 128, physical pages **10630–10631** (printed 10618–10619), defines the two one-sided tests, their maximum p-value, and the additional `100*(1-2*alpha)%` interval. Physical p.10613 specifies the option grammar/default bounds; physical p.10644, Table 128.9, identifies **EquivLimits** and **EquivTests**.

[ttest_tost.zig](../../../src/stat/ttest_tost.zig) provides isolated option parsing, delayed bound resolution, difference/log-ratio inference, and rendering. It does not change existing fit APIs. Difference inputs use the original analysis scale. Log-ratio estimates and SE use natural-log units, while bounds, estimates, and intervals are displayed on the original positive scale. Normal-ratio Fieller inference is not implied by log-ratio support.

## API and exact invocation contract

- `parseOption(tokens, index, diagnostics) !RawBounds`: index initially points at TOST and advances past `)`. Accepts `TOST(upper)` or `TOST(lower,upper)`, signed numeric literals, and scientific notation.
- `resolveBounds(raw, h0, scale, diagnostics) !Bounds`: call **after** all header options and H0/DIST defaults. Omitted lower is `2*H0-upper` for differences or `H0/upper` for ratios. Bounds must be finite and strictly ordered; ratio bounds must be positive.
- `evaluate(estimate, se, df, bounds, alpha, scale) !Result`: computes right-tail test at the lower bound (SAS label **Upper**), left-tail test at the upper bound (**Lower**), maximum p-value, additional interval, and containment assessment. Existing pooled/Welch or one-sample summaries supply estimate/SE/DF.
- `Row`, `renderAssessment`, and `renderTests` emit EquivLimits and EquivTests. Class rows carry `Diff (1-2)`, method, and variance-assumption labels. One-sample/paired rows use no CLASS header. Two extra helpers, `renderLognormalStatistics` and `renderLognormalIntervals`, preserve ordinary lognormal tables without emitting the ordinary t test.

The shared hook must retain ordinary Statistics and ConfLimits, substitute EquivLimits/EquivTests for ordinary TTests, and retain Equality for CLASS analyses. Track whether SIDES was explicitly supplied: SAS warns `The SIDES option is ignored when using the TOST option.` even for explicit SIDES=2, and ordinary intervals must remain two-sided. No warning is emitted when SIDES is omitted. Retain a visible guard for Cochran-specific TOST, which this helper does not implement; existing unsupported normal-ratio and two-group lognormal paths remain guarded.

## Numerical and boundary checks

Five inline numerical tests pass, and 23 focused TTEST runner tests pass after shared-file integration. They include the entire unchanged printed oracle, parser failures with captured locations, both tails, maximum p, confidence level, class/sign reflection, original-scale log-ratio margins, and degenerate cases.

- Independent exact boundary: observations (-1,1) have mean=0, SE=1, DF=1. Student(1) is Cauchy, so margins (-1,1), alpha=0.25 give both p-values exactly 0.25 and the 50% interval [-1,1]. SAS assesses this boundary **Equivalent**. Tighter margins are not equivalent; wider margins are equivalent. No oracle-derived epsilon changes the decision.
- Student(1) uses its analytic Cauchy tail and quantile identities; other degrees of freedom reuse existing Student probability/inverse functions. The implementation has no dataset-specific constants or source-derived probability tolerances.
- Independent ratio case: log observations (-0.1,0,0.1) have mean=0, variance=0.01, SE=sqrt(0.01/3), DF=2. Margins (0.8,1.25) are checked with elementary Student(2) tail/quantile formulas. Multiplying the ratio estimate and both margins by ten preserves both p-values and scales the interval by ten.
- Zero SE retains signed infinite statistics when the numerator is nonzero. A zero numerator gives a missing test; the overall p stays missing if either test is missing. SAS still assesses a collapsed interval at a bound as contained. Tests distinguish containment from a fabricated finite p-value.
- Invalid/reversed/equal bounds, nonpositive ratio bounds, malformed numeric arguments, negative SE, invalid DF, and nonfinite inputs fail visibly. ALPHA follows SAS's `0<alpha<1` acceptance; at/above 0.5 the additional endpoints coincide/reverse rather than silently changing alpha.

Analytic floating-point checks use fixed `1e-12` to `1e-14` tolerances according to the arithmetic involved; exact Cauchy quarter probabilities are checked for equality. Printed oracle comparison uses **no numeric tolerance**: every token, sign, digit, missing marker, arrow, assessment, label, and row must match, with only whitespace ignored.

## Original-program and independent SAS evidence

On 2026-11-25 the real OpenSAS CLI, after integrating the hook on top of the landed paired-design implementation, executed the **unchanged original** `tost_difference.sas`, including its DATA step and header options. Actual/expected status was **0/0**, stderr was empty, and every expected listing token matched. The comparison covers ordinary summaries/95% intervals, both methods' 90% equivalence intervals and assessment arrows, both one-sided t tests and null values, overall p-values, and the folded-F table.

The same real build passed the original TTEST-007, TTEST-006 (paired direction), TTEST-005 (one-sided court), TTEST-003, TTEST-002, TTEST-001, and COMMON-005 programs with exit 0, empty stderr, and complete token equality. The invalid-ALPHA TTEST-005 case also retains its existing contract: empty listing, OpenSAS CLI exit 1 (D-009 user-program error), SAS reference severity status 2 (error), and actual diagnostic `ERROR(expanded L2): PROC TTEST: ALPHA must be between 0 and 1`. Its raw exit integers and diagnostic wording are not claimed identical to SAS; see the existing TTEST-005 verification record. A separate live SAS 9.4 check on responses (0.9,1,1.1), `DIST=LOGNORMAL H0=1.2 TOST(1.5)`, also matched every token: the omitted lower bound resolves to 0.8. Live SAS probes independently established the exact-boundary, zero-SE, invalid-bound, and explicit-SIDES behaviors above.

**Integration status:** the real shared parser/execution hook is implemented. It preserves paired summaries and labels, ordinary normal/lognormal output when TOST is absent, and existing fitting APIs. Integrated tests exercise the original CLASS oracle, normal/lognormal/paired TOST invocation, delayed H0 resolution, explicit-SIDES warnings, and captured invalid-summary errors. The final exact-SHA authoritative gate and unit count are reported separately after committing this evidence; earlier unimported-module gates are not substituted for it. Normal-ratio, two-group lognormal, paired-logratio, and Cochran-specific TOST remain explicit unsupported paths. ODS dataset capture/registry expansion is outside this change; renderers use the documented EquivLimits/EquivTests producer names.

## Reproduction

Build and compare the integrated implementation from the repository root:

```sh
/Users/thomas/.local/share/zig-0.16.0/zig build -j2
python3 - <<'PY'
from pathlib import Path
import subprocess
base = Path('tests/STAT15.4-oracle/STAT-TTEST-009/tost_difference')
r = subprocess.run(['zig-out/bin/opensas', str(base)+'.sas'], capture_output=True, text=True)
assert r.returncode == int(Path(str(base)+'.expected.rc').read_text())
assert r.stderr == '', r.stderr
assert r.stdout.split() == Path(str(base)+'.expected.txt').read_text().split()
print('Original TOST oracle: complete output/status/diagnostics PASS')
PY
/Users/thomas/.local/share/zig-0.16.0/zig build gate -j2 --summary all
```

Capture the gate's subprocess return code directly (not an unguarded pipe/tee), its full summary/unit count, and `git rev-parse HEAD`. A successful standalone harness or isolated prototype is not a substitute for that integrated gate.
