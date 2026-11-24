# STAT-VARCLUS-009 — VARCLUS — Official examples and feature integration regression

## Source

S154 / Chapter 129 / `Getting Started: VARCLUS Procedure` (PDF pp. 10696–10699); S154 / Chapter 129 / `Overview: VARCLUS Procedure` (PDF pp. 10694–10696).

## Scope

Convert this chapter's Examples and Getting Started sections into replayable cases using public data, exercising feature combinations and defaults; explicitly list prerequisites for examples involving other procedures or external products.

## Acceptance criteria

Record inputs, options, expected tables/data sets/graphs, and reference values for every example; pass every example explicitly within this procedure's scope; itemize unmet external prerequisites and link them to tasks; skipped or merely successful runs do not count as numerical validation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 129.1: Correlations among Physical Variables |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Reads the published correlation matrix as list values instead of lost seven-column numeric fields.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
