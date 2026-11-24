# STAT-TREE-005 — TREE — Displayed Output / ODS Table Names

## Source

S154 / Chapter 127 / `Displayed Output` (PDF p. 10584); S154 / Chapter 127 / `ODS Table Names` (PDF pp. 10584–10585).

## Scope

Implement Displayed Output; ODS Table Names. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Displayed Output / ODS Table Names, verify table names, labels, triggering conditions, rows, columns, degrees of freedom, statistics, and missing representations; exercise selection and capture with ODS TRACE/OUTPUT; unrelated options must not create extra tables.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TREE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Uses list input and underscore-separated country labels so protein measurements retain their fields. Traditional TREE graphics use a temporary SVG destination.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
