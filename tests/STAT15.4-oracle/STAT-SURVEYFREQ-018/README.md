# STAT-SURVEYFREQ-018 — SURVEYFREQ — Displayed Output / ODS Table Names

## Source

S154 / Chapter 118 / `Displayed Output` (PDF pp. 9672–9679); S154 / Chapter 118 / `ODS Table Names` (PDF pp. 9679–9681).

## Scope

Implement Displayed Output; ODS Table Names. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Displayed Output / ODS Table Names, verify table names, labels, triggering conditions, rows, columns, degrees of freedom, statistics, and missing representations; exercise selection and capture with ODS TRACE/OUTPUT; unrelated options must not create extra tables.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
