# STAT-TTEST-007 implementation evidence

Recorded 2026-11-25 for implementation commit `62ed1811e2fc87995327522c06e4d6ea3297805c` on `codex/stat-dev4`. This document adds evidence only; the original program, expected output, status, and SAS log are unchanged. The final evidence-commit SHA and authoritative gate summary must be reported separately after that commit is tested.

## Sources and implemented scope

- [Fixture README](README.md), [original program](two_sample_variance.sas), [expected complete listing](two_sample_variance.expected.txt), [expected status](two_sample_variance.expected.rc), and [SAS reference log](two_sample_variance.oracle.log).
- [SAS/STAT 15.4 User's Guide](../../../docs/SAS-STAT-15.4-Users-Guide.pdf), Chapter 128, **physical PDF pages 10624–10629** (printed 10612–10617). Normal-difference formulas are on physical 10624–10626: pooled SD/SEM and mean intervals; Satterthwaite DF; Cochran–Cox probabilities; folded-F equality of variances. Ratio methods on 10626–10629 are outside the implemented path.
- [Numerical core and six inline tests](../../../src/stat/ttest_two_sample.zig), [CLASS invocation and integrated tests](../../../src/stat/ttest.zig), [COCHRAN parsing](../../../src/stat/ttest_parse.zig).

Implemented: `DIST=NORMAL TEST=DIFF`, pooled and Satterthwaite/Welch tests, optional Cochran–Cox, folded-F, one-/two-sided mean intervals, `CI=EQUAL` and suppression with `CI=NONE`. Group labels and summaries come from existing CLASS selection. Frequencies determine N/DF; precision weights determine the SEM denominator independently. Existing normal/lognormal one-sample paths are retained.

## Original-program verification

The actual CLI executed each original `.sas` file, including its DATA step and procedure declarations. No shortened program or substituted expected output was used. Comparison tokenizes both complete listings on whitespace and requires identical tokens in identical order, with no extra tokens. Only whitespace/layout is normalized: labels, signs, missing markers, digits, p-value strings, and every result row must match exactly.

For TTEST-007 this checks both class rows (N, mean, SD, SEM, minimum, maximum); pooled and Satterthwaite difference rows; all class and difference mean limits; all displayed SD limits; method/variance labels; DF, t, and p for all three methods; and folded-F numerator DF, denominator DF, statistic, and p. The printed oracle values are compared exactly, not through a broad numerical tolerance.

| Original case | Actual / expected exit | Actual stderr | Complete output tokens |
|---|---|---|---|
| STAT-TTEST-007 `two_sample_variance.sas` | 0 / 0 | empty | match |
| STAT-TTEST-003 `normal_lognormal.sas` | 0 / 0 | empty | match |
| STAT-TTEST-002 `court_default.sas` | 0 / 0 | empty | match |
| STAT-TTEST-001 `by_frequency_weight.sas` | 0 / 0 | empty | match |
| STAT-COMMON-005 `tails_and_intervals.sas` | 0 / 0 | empty | match |

There are no warnings or errors in these OpenSAS runs. The original SAS logs retain their normal lifecycle notes; those logs were not edited or filtered to manufacture diagnostic agreement.

## Independent numerical checks and precision

Six inline core tests and 16 focused TTEST runner tests passed before the evidence-only commit. The core checks include the complete table oracle, hand calculations, weights, sided tests/H0, class reversal, invalid summaries, degenerate variance, and a 3-versus-300 sample-size comparison. The focused tests include actual CLASS/COCHRAN invocation, the existing one-sample/lognormal tests, and captured fail-loud behavior for unsupported lognormal CLASS analysis.

- Hand case A=(1,2,3), B=(3,4,5): difference=-2, each variance=1, pooled/Welch SEM=sqrt(2/3), DF=4, folded-F=1. Cochran DF=2 gives the independent probability `1-sqrt(3)/2`. Fourfold precision weights double SD without changing N, DF, SEM, or t probabilities.
- Unequal case A=(1,2,3), B=(3,4,5) repeated 100 times: N=3/300, means=2/4, CSS=2/200. Separate live SAS 9.4 ODS `TTests`, `Equality`, and `ConfLimits` output, printed with `BEST32.`, verified pooled DF=301, Welch DF=2.02684473070816, pooled t=-4.20762957641104, Welch t=-3.45257379077274, and folded-F p=0.4518399377042. Cochran's displayed DF is missing for unequal N, as specified on physical p.10626.
- Independent 128-node Gauss–Legendre integration of the t(299) density, combined with the elementary Student(2) inverse, gives Cochran p=0.07419586760210986. The implementation matches within `1e-12` absolute. SAS reports 0.07419587100656, differing by 3.405e-9; that separate comparison has an explicitly bounded `5e-9` tolerance. The displayed result is identical. Other high-precision reference checks use field-specific `1e-12` through `1e-9` absolute tolerances, documented in the tests.
- Numeric comparisons to four-decimal oracle fields use half a display unit (`5e-5`); this does not loosen the exact complete-listing token comparison.
- Physical p.10626 says `n1+n2-1` for the pooled SD interval, but the unchanged SAS oracle uses residual DF=`n1+n2-2`. The code follows the observed result: pooled SD 20.4992 has limits [14.3231,35.9747].

## Reproduction commands

Run from the repository root with Zig 0.16.0. Build before running the CLI check:

```sh
/Users/thomas/.local/share/zig-0.16.0/zig build
python3 - <<'PY'
from pathlib import Path
import subprocess
cases = [
    ('STAT-TTEST-007', 'two_sample_variance'),
    ('STAT-TTEST-003', 'normal_lognormal'),
    ('STAT-TTEST-002', 'court_default'),
    ('STAT-TTEST-001', 'by_frequency_weight'),
    ('STAT-COMMON-005', 'tails_and_intervals'),
]
for ticket, case in cases:
    base = Path('tests/STAT15.4-oracle') / ticket / case
    run = subprocess.run(
        ['zig-out/bin/opensas', str(base) + '.sas'],
        text=True, capture_output=True,
    )
    assert run.returncode == int(Path(str(base) + '.expected.rc').read_text())
    assert run.stderr == '', (ticket, run.stderr)
    assert run.stdout.split() == Path(str(base) + '.expected.txt').read_text().split(), ticket
    print(ticket, 'PASS: complete listing, status, empty diagnostics')
PY
/Users/thomas/.local/share/zig-0.16.0/zig build gate --summary all
```

The module is now imported by the actual TTEST execution path, so the final integrated gate includes its inline tests rather than relying solely on a temporary harness. Record `git rev-parse HEAD`, the gate process exit status, and the full summary (including unit-test count) for the final evidence commit.

**Gate status at evidence preparation:** the earlier log for `62ed1811` contains `error: unable to write cache manifest: NoSpaceLeft`. Its corpus (2305/2305) and programs (11/11) substeps passed, but this is **not an accepted green gate**. An earlier green report is superseded. The required final `gate --summary all` must be a distinct verified retry after the manager releases the disk-pressure pause; no result is presumed here.

## Remaining unsupported scope

Two-group `DIST=LOGNORMAL`, `TEST=RATIO` (including Fieller/Sasabuchi normal-ratio methods), and `CI=UMPU` remain explicit gap diagnostics. The normal-difference numeric core requires at least two replicated observations per class and rejects invalid/nonfinite summaries. This evidence proves the supplied original normal-difference oracle and the stated regression cases, not untested ratio, crossover, bootstrap, or graphics methods.
