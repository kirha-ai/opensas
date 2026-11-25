# STAT-FREQ-005 — chi-square verification and labeled BY reports

Starting base: `c5d20ae1a4043cd9f7e83c94e4a2fe1520bee4a2`. Branch: `codex/stat-dev3`.
Read the full ticket, own README, unchanged case and complete expected listing/log, physical
manual pages 3165–3170 and the original Example 47.3 on pages 3263–3266. All oracle files
remain unchanged. No numerical kernel was changed; no blanket tolerance was applied.

## Concrete fixes

Baseline status was 0 and all numerical values matched, but only 103 tokens were displayed
versus 110 expected: BY labels used the variable name, the second group omitted the title,
and the table rule was one character too wide. FREQ now uses labels in a display-only BY
descriptor, preserves original names for grouping/lookup/output, and sizes the expected-value
stub correctly. A regression pins both groups, their labels, rules and original descriptor.

The manager explicitly authorized a narrow shared extension in `src/proc.zig` and `src/main.zig`.
The optional full title context is populated only for FREQ. FREQ invokes the existing
`emitTitles`/`emitTitlesBy` for each group that actually contributes listing output, using
original BY names, labels and formatted values. The outer FREQ wrapper no longer duplicates
the first title. No global title parser/emitter was changed. Shared changes were committed in
source commit 536e0233 before main/proc ownership was released back to GLM.

`freq_by_titles.sas` covers two title lines, named/positional BY substitutions with formatted
values, title cancellation, and one-time non-BY emission. The zero-margin unit test now covers
both a zero row and its transposed zero column and requires no fabricated chi-square result.
Two existing expected-value goldens change only spacing/rule width; every numeric token was
checked unchanged. Expected goldens are committed separately from source and evidence.

## Reproducible full comparison

After building, run from the repository root with a fresh output directory:

```sh
python3 tests/STAT15.4-oracle/STAT-FREQ-005/verify.py --output /absolute/fresh/output-directory
```

The replay saves complete actual stdout/stderr/status, both SVGs, the independent two-way
regression output and a manifest. `dev3-verification.json` records the checked hashes and
calculations. SVG note paths in stderr depend on the chosen output directory; no log content
is removed. Final build SHA/base and direct-exit `gate -j2` counts are in the handoff.

The unchanged documented_feature case matches **all 110 tokens**, in order, after collapsing
whitespace runs and trimming edges only. Status is **0**, as expected. Actual and reference
warning/error sets are empty. Actual informational diagnostics are two SVG-written notes;
SAS source echoes, workspace deletion/read and page notes differ and are not claimed exempt.
No titles, BY headings, table rules, fields, counts, probabilities or diagnostics were dropped.

## Independent calculations, without blanket numerical tolerances

The verifier aggregates all 27 original DATALINES records independently, in DATA order.

| Region | Observed counts | N | Expected counts | Exact Pearson statistic | Printed statistic / p |
|---|---|---:|---|---|---|
| 1 | 76,19,83,65,3 | 246 | 73.8,29.52,73.8,61.5,7.38 | 1909/246 | 7.7602 / 0.1008 |
| 2 | 152,94,134,117,19 | 516 | 154.8,61.92,154.8,129,15.48 | 8275/387 | 21.3824 / 0.0003 |

DF is exactly 5-1=4. Probabilities use the independent closed form
`exp(-chi/2)*(1+chi/2)` evaluated with 60-digit Decimal arithmetic. They are
0.1007695128392702979 and 0.00026590357616432555. The manifest retains the unrounded
formula values; comparison to the listing uses its specified four-decimal representation,
not a blanket absolute-error threshold. Both groups have no expected counts below five.

For the existing public regression table [[1,9],[11,3]], the independent expected counts are
[[5,5],[7,7]]. Pearson is 384/35; continuity-adjusted chi-square is 42/5; Mantel-Haenszel is
368/35. The verifier also calculates the likelihood ratio directly from `2*sum(O*log(O/E))`.
DF=1 probabilities use `erfc(sqrt(chi/2))`; every displayed statistic/probability row matches
its independently formatted value exactly. The complete existing regression golden also matches.

Existing unit/corpus coverage retains specified TESTP/TESTF, DF adjustments, fractional counts,
small expected-count warnings, single-category DF=0 and zero-total behavior. Captured-diagnostic
coverage checks warning controls and zero margins; no actual aborting process was added.

## Graph inspection

Both freshly generated deviation dot plots were rendered and inspected against the manual's
plots on physical pages 3265–3266. Five categories, signs, relative deviations, group labels,
axes and p-value annotations are correct; no clipping/overlap was observed. Styling and p-value
placement differ from SAS, and no pixel-identical claim is made.

Every plotted count is checked exactly. For each point the manifest records the exact rational
relative deviation, actual SVG data-value, and their unrounded Decimal difference (typically
floating-point rounding). No such difference is discarded or hidden by a tolerance. Dot x
coordinates agree exactly at the SVG's two-decimal coordinate precision when calculated from
the rational deviation and the displayed axis limits. SVG hashes preserve the checked images
reproducibly without committing duplicate rendered images or full listings.
