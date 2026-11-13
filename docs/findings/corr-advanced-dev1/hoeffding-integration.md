# Public Hoeffding probability integration — dev1

Dependency: manager-landed 31701c208f7f503c71f1cc90f42602331ba4431c,
`corr_hoeffding_probability.zig`, owned and independently validated by dev5.
No calibration coefficients, distribution rules or support-module tests were
changed or duplicated.

`corr_advanced.hoeffding` now assigns `probability(result.r,result.n)` after
computing SAS's scaled D. The parser's former HOEFFDING-without-NOPROB rejection
is removed. Rendering uses the existing probability column, preserving NOPROB,
NOSIMPLE, NOPRINT and typed Pearson/advanced separation. The ODS advanced-mode
capture guard remains unchanged and is exercised through the real run path.

## Public acceptance checks

`hoeffding-public-precision.sas/txt` was run against actual SAS 9.4 M9 with:

    /Users/thomas/sas/bin/sasrun /private/tmp/dev1-corr-hoeffding-public-precision.sas -f text -o - -l /dev/null

It reports zero errors/warnings. The input includes BY groups for:

| Group | Case | Pair N | SAS D | SAS probability |
|---|---|---:|---:|---:|
| 1 | untied permutation | 8 | 1/56 | .27035003097535 |
| 2 | perfect order | 5 | 1 | missing |
| 3 | perfect order | 6 | 1 | 0 |
| 4 | ties, FREQ=2.9 truncation, zero/missing FREQ exclusions | 9 | -1/7 | 1 |
| 5 | different missing rows in x/y | 6 | 0 | .36426667551153 |
| 6 | constant margin | 6 | -.625 | 1 |
| 7 | too few pairs for D | 4 | missing | missing |

The oracle also expands FREQ explicitly and obtains the same results. It repeats
all groups with NOPROB to verify suppression. Full-precision ODS is used only in
the SAS oracle, not as a claim of new interpreter ODS schemas.

The runnable CORR tests additionally retain the medium-statistic and N=12
probability discriminators, tied coefficients/diagonals and both constant margins.
Integration assertions use 5e-13 absolute for full-precision p references,
1e-10 for rational coefficients, and 5e-5 for probabilities available only as
four-decimal listing values. The standalone module's independent 510 holdouts
and range certification remain dev5 evidence, not new dev1 tests.

`tests/corpus/corr_hoeffding_inference_dev1.sas/.txt` pins the compact public
listing for ordinary, NOPROB and expanded-FREQ runs. It is checked against the
retained SAS run; expected output is committed separately from implementation.

Hoeffding probability integration is accepted on this coverage. Full parent-ticket
completion is still blocked by tight-tolerance polychoric singular-information
compatibility; see `singular-information.md`. No unrelated grammar section or
ODS producer was modified.
