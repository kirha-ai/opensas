# NOTE-freqallmissnone — dev2

Base: bdfcd4f56fec199f65a859a5fccbd88eb58ca3ea. Synthetic data only.

Read CLAUDE.md, src/lexer.zig, D-029 and Statistical Procedures printed
pp.156–158 and 235–237 before implementation. The statistical reference is
available read-only at /Users/thomas/kirha/opensas-private/docs/sas94-procedures-statistical.txt.

## Oracle evidence

SAS 9.4M9, invoked with:

```
/Users/thomas/sas/bin/sasrun /Users/thomas/kirha/opensas-dev2/docs/findings/NOTE-freqallmissnone-probe.sas -f text -o /Users/thomas/kirha/opensas-dev2/docs/findings/NOTE-freqallmissnone-probe.txt -l /Users/thomas/kirha/opensas-dev2/docs/findings/NOTE-freqallmissnone-probe.log
```

The adjacent .sas/.txt/.log files retain the final probe, listing and log.
The final probe reports no errors or warnings. The zero-strata .txt/.log
files are a second SAS run of tests/corpus/freq_stmt_opts.sas.

- Empty input: no FREQ listing; OUT= has zero rows and the requested schema;
  NOTE: No observations in data set WORK.EMPTY.
- Two missing observations: table heading/column headings, no category rows,
  Frequency Missing = 2. OUT= stores the missing category, COUNT=2,
  PERCENT/CUM_FREQ/CUM_PCT missing.
- MISSPRINT: missing category displayed, excluded from percent/cumulative
  bases; MISSING: included in the base, 100 percent for an all-missing table.
  MISSING takes precedence when both options appear.
- BY missing values form their own group; OUT= carries BY columns and each
  group's percentages. DESCENDING/NOTSORTED use existing interpreter helpers;
  unsorted or absent BY variables produce captured diagnostics.
- Zero weights excluded by default, including entire zero-weight BY groups;
  SAS reports a zero-nonzero-weights NOTE. ZEROS retains observed zero-count
  categories; a zero denominator yields missing percentages, not zero or 100.
- Formatted category containing blank and X (weights 1 and 2) is wholly
  missing: COUNT=3, missing percentages without MISSING; the other category
  (weight 3) gets 100 percent. MISSING gives 50/50. OUT= retains the lowest
  raw value and format. Format classification occurs within each BY group.
- Two-way MISSPRINT retains missing cells without adding them to margins or
  percentage bases. Default all-missing dimensions print the SAS diagnostic;
  no complete observations prints Sample Size = 0 and Frequency Missing.

The corpus fixture uses explicit blank character assignment (avoids a separate
DATA-step list-input dot-as-character issue) and PROC PRINT FORMAT c $1. to
expose raw OUT values (avoids a separate PRINT format-removal limitation).
Listing geometry follows the existing OpenSAS renderer; SAS oracle comparisons
are of counts, denominators, output rows, missingness, and diagnostics.

## Scope and checks

New independent missing/percentage computation policy is in src/stat/freq.zig;
existing FREQ parsing/rendering and dispatch remain in proc.zig. Shared format
helpers have a FREQ-only switch; MEANS/TABULATE behavior remains unchanged.
The EBNF records BY and MISSPRINT support; no SAS function tracker change is
needed because this adds no DATA-step functions.

Three unit regressions cover OUT values, empty schemas, zero weights,
BY ordering errors, and formatted missing categories. The integration fixture
covers one- and two-way listings and OUT= in the same cases. Earlier BY and
MISSPRINT gap fixtures now exercise their supported behavior.

Pre-landing checks: unit 1004/1004; corpus 1966/1966. Final gates are rerun after
the single required rebase and reported with exit codes in the landing report.
Expected-output updates are isolated in a separate evidence-citing commit.

The broader GAP-freq-table-complete task is not implemented here. In particular,
its n-way global level support, whole-table OUT denominator, LIST/CROSSLIST,
SPARSE/NOSPARSE, negative weights and general display controls remain follow-up
work. The extra n-way oracle probe retains useful evidence of global levels;
it is not used to claim that broader table task is complete.
