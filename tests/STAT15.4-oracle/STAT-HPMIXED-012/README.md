# STAT-HPMIXED-012 — HPMIXED — Default Output / ODS Table Names

## Source

S154 / Chapter 62 / `Default Output` (PDF pp. 4848–4849); S154 / Chapter 62 / `ODS Table Names` (PDF pp. 4849–4850).

## Scope

Implement Default Output; ODS Table Names. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Default Output / ODS Table Names, verify table names, labels, triggering conditions, rows, columns, degrees of freedom, statistics, and missing representations; exercise selection and capture with ODS TRACE/OUTPUT; unrelated options must not create extra tables.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 62.3: Using PROC GLIMMIX for Further Analysis of PROC HPMIXED Fit |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
