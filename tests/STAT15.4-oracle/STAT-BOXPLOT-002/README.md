# STAT-BOXPLOT-002 — BOXPLOT — Grouped box plot summary statistics and default graph data

## Source

S154 / Chapter 32 / `Getting Started: BOXPLOT Procedure` (PDF pp. 1368–1376); S154 / Chapter 32 / `Overview: BOXPLOT Procedure` (PDF pp. 1366–1368).

## Scope

Implement grouped box plot summary statistics and default graph data using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Grouped box plot request and the corresponding explicit distribution summaries |

**documented_default:** Public SASHELP input replaces the longer printed turbine example; text statistics and the graph request are captured, with visual comparison tracked separately.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
