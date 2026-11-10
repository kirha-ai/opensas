# GAP-freq-table-complete — dev2

Original base: 566727e09c7d190bef50bd690e5bc38584f0f895, after NOTE-freqallmissnone
landed. Work is confined to opensas-dev2. All fixture data are synthetic.
No jira edits, fetch/pull, push, or midtask rebase.

Read CLAUDE.md, lexer.zig and D-029. Manual: Base SAS 9.4 Procedures Guide:
Statistical Procedures pp.78–80, 103–106, 120–126, 148–160, 235–242. The ignored
reference was read from opensas-private/docs/sas94-procedures-statistical.txt.

## Implementation and acceptance

- Existing dispatch delegates to src/stat/freq.zig. Its parser, orchestration,
  output builder and renderers are separate functions. src/stat/freq_table.zig
  is a pure typed sparse table/score/cell-metric implementation, with no lexer,
  dataset or rendering dependency. Shared helpers remain in proc.zig.
- Default requests exclude BY and WEIGHT variables. Explicit lists support
  parenthesized Cartesian products (first factor varies fastest), numbered
  ranges including padded suffixes, descriptor ranges, prefixes and special
  variable lists. Bare TABLES, stray parentheses, flag=value, incompatible
  LIST/CROSSLIST and SPARSE/NOSPARSE, invalid MAXLEVELS and FORMAT widths error.
- INTERNAL, FORMATTED, DATA and weighted FREQ ordering is global within each
  BY group; missing categories always lead. Formatted categories keep their
  lowest raw representative and inherit missingness. BY retains ordered or
  NOTSORTED contiguous groups, validates direction, and formats BY labels.
- Missing weights are excluded; zero weights are excluded unless ZEROS.
  Negative weights remain signed and suppress percentages and cell statistics.
  ZEROS implies SPARSE, overridden by NOSPARSE. One-way zero-count OUT rows
  remain even with NOSPARSE (verified against SAS). Negative cells in a row
  whose signed sum is zero remain in CROSSLIST/NOSPARSE; its zero subtotal is
  suppressed. Formatted WEIGHT variables retain their numerical analysis weight.
- N-way dimensions use global levels, including empty combinations of controlling
  variables. Empty strata report Sample Size = 0 with their proper table number.
  LIST is one whole n-way cumulative listing; CROSSLIST is per-stratum with
  margins. LIST/LINE includes row numbers. The legacy TABLE marker has no
  effect in these destinations, verified in controls2.sas.
- EXPECTED, DEVIATION, CELLCHI2, CUMCOL, TOTPCT, PEARSONRES and STDRES use the
  same typed counts/margins as OUT=. NOFREQ suppresses grid cells but retains
  marginal frequency counts. CROSSLIST columns honor suppression independently.
- OUT= belongs to the last expanded request of each TABLES statement and uses
  whole-table PERCENT. OUTPCT adds PCT_ROW/PCT_COL and n-way PCT_TABL; OUTEXPECT
  precedes PERCENT in the schema. OUTCUM applies only to one-way output. Rows
  follow displayed level order, retain raw values, formats, labels, informat,
  lengths, BY columns and SAS-generated statistic labels. Repeated TABLES
  variables occupy one OUT column and issue the SAS-style warning.
- NLEVELS reports total, missing and nonmissing levels, and variable labels when
  present. MAXLEVELS changes only the one-way display, not counts or OUT=.
  FORMAT applies to grid counts/expected/deviation; FORMCHAR changes actual
  separators. Field widths avoid overwriting neighboring values.

The destination audit is explicit: PAGE and COMPRESS need pagination and
CONTENTS needs ODS contents metadata; these return named rc-2 gaps rather than
pretending to act. PAGE+COMPRESS together is a SAS syntax error (rc1). This is
the outside-ticket destination policy authorized by the manager. Documented
context-specific behavior is retained: one-way NOFREQ/NOROW/NOCOL and LIST do
not alter that display; FORMAT/CUMCOL do not alter CROSSLIST; residual options
outside CROSSLIST warn; SCOROUT alone emits no score table without statistics.
No DATA-step function was added, so the EBNF is the relevant tracker.

## Typed matrix handoff to dev4

`freq_table.Table` holds `dimensions`, `strides`, sparse `counts`, `total`,
`missing`, `negative`, `include_missing` and parsed `score_kind`. A Level has a
formatted `value`, typed lowest `raw`, `missing` flag and weighted `frequency`.
`computeTable` in freq.zig creates this representation from the existing
formatted dataset view and helpers. The `tab` local in runFreq is the integration
point before rendering or TABLES NOPRINT skips the listing.

`Table.matrix(allocator, stratum)` returns `?ScoredMatrix`. Its `matrix` has the
agreed fields `rows`, `cols`, row-major `counts`, optional `row_scores` and
`col_scores`; convert with an ordinary struct literal to freq_tests.CountMatrix.
One-way matrices have one column. Row/column levels excluded by missing policy
are omitted; MISSING makes those categories valid. Negative weights return null
so no inference kernel can accidentally analyze them. `row_levels` and
`col_levels` accompany the matrix. Numeric TABLE scores use the lowest internal
value; character TABLE scores are ordinal. RANK is weighted midrank, RIDIT is
rank/N, MODRIDIT is rank/(N+1). When numeric missing values make TABLE scores
invalid, SAS's printed ordinal fallback is retained and
`numeric_table_scores_valid=false` informs the inference adapter of that fact.

`Table.slice` provides per-stratum margins and metrics. A subtle SAS distinction:
OUT PERCENT is missing for a missing controlling value unless MISSING is used,
but MISSPRINT's conditional grid TOTPCT still divides its nonmissing row/column
cell count by the global nonmissing table total. The final displays probe and
unit regression pin this (count2/global4 => 50%, while OUT PERCENT is missing).

Inference hookup remains dev4-owned. The current recognized statistical options
stay explicit gaps until integration. In particular, **do not reject LIST+stats**:
the manager's real-SAS result overrides the manual wording. After TEST
implications, switch only affected LIST requests to grid; preserve separate
LIST-only requests. LIST+CROSSLIST is a separate validated syntax error.
TABLES NOPRINT must not suppress the later statistics renderer.

## Oracle evidence and regression checks

Each `GAP-freq-table-complete-*.sas` has adjacent retained `.txt` and `.log` files.
Reproduce with `/Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o
/absolute/probe.txt -l /absolute/probe.log`. DATA _NULL_ PUT checks use FILE PRINT.

- `semantics`: 86 OUT rows, **668 whitespace-normalized tokens exactly equal to
  SAS**, including expected counts, all percentage denominators, sparse cells,
  signed weights, last-request output, ordering, BY, MAXLEVELS and formatted
  WEIGHT. SAS line wrapping is the only normalization. Zero oracle errors.
- `displays`: LIST, CROSSLIST, global and empty strata, extra cell statistics,
  suppression, NLEVELS, MAXLEVELS, FORMCHAR/FORMAT and missing controls. Zero
  oracle errors/warnings. Existing OpenSAS listing indentation is retained;
  numeric fields and table structure, not SAS page breaks, are pinned.
- `existing`: exact synthetic sources of all seven changed existing goldens;
  zero oracle errors/warnings. Changes are signed-weight handling, whole-table
  OUT percentages, global levels/order, raw formatted output order/metadata,
  and newly supported LIST/prefix crossings.
- `interactions`: signed cancellation with CROSSLIST/NOSPARSE, and the one-way
  NOSPARSE exception. Zero oracle errors/warnings (negative-weight notes expected).
- `probe`: initial broader grid/list/score study, including independent SAS
  CHISQ/SCOROUT output used only to validate scores, not to claim integration.
- `controls`: default TABLES, scoped display options and residual warnings;
  the intentional SPARSE+NOSPARSE case errors.
- `controls2`: NOFREQ marginals, all cell fields suppressed, LIST/LINE, generated
  metadata and duplicate variables; the duplicate-variable warning is expected.
- `metadata`: labels, lengths, formats, aliases and MAXLEVELS; bare TABLES is an
  intentional invalid case.
- `invalid`: independent SAS validation of stray (CHISQ), MISSING=0,
  LIST+CROSSLIST, SPARSE+NOSPARSE, MAXLEVELS=0, FORMAT width30, PAGE+COMPRESS.

New corpus fixtures: freq_table_semantics, freq_table_displays,
freq_table_signed_cancel. Direct tests cover strict parser errors/gaps, default
requests, metadata, Cartesian order, padded ranges, all score types, typed
matrices, residuals, missing-control percentages and numerical column isolation.
The previous FREQ gap fixtures now test supported behavior. The formerly invalid
COMPRESS+PAGE positive fixture now uses supported options; its invalid and
separate destination-gap cases are tested with captured diagnostics.

Before landing: commit implementation/evidence separately from expected-output
updates, perform the required single rebase, and run all three final gates with
exit codes and counts in the landing report. Pre-rebase unit check:1011/1011;
programs:11/11. No new unrelated ticket is started.
