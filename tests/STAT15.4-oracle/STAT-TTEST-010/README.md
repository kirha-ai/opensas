# STAT-TTEST-010 — TTEST — Displayed Output / ODS Table Names

## Source

S154 / Chapter 128 / `Displayed Output` (PDF pp. 10640–10644); S154 / Chapter 128 / `ODS Table Names` (PDF p. 10644).

## Scope

Implement Displayed Output; ODS Table Names. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Displayed Output / ODS Table Names, verify table names, labels, triggering conditions, rows, columns, degrees of freedom, statistics, and missing representations; exercise selection and capture with ODS TRACE/OUTPUT; unrelated options must not create extra tables.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [ods_tables.sas](ods_tables.sas) | captured | 0 | [listing](ods_tables.expected.txt) / [log](ods_tables.oracle.log) | ODS table names, row/column content, full-precision numeric values and descriptor |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
