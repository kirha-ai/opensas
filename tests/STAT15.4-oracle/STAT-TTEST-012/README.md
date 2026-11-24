# STAT-TTEST-012 — TTEST — Official examples and feature integration regression

## Source

S154 / Chapter 128 / `Examples: TTEST Procedure` (PDF pp. 10650–10689).

## Scope

Convert this chapter's Examples and Getting Started sections into replayable cases using public data, exercising feature combinations and defaults; explicitly list prerequisites for examples involving other procedures or external products.

## Acceptance criteria

Record inputs, options, expected tables/data sets/graphs, and reference values for every example; pass every example explicitly within this procedure's scope; itemize unmet external prerequisites and link them to tasks; skipped or merely successful runs do not count as numerical validation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [summary_statistics_example.sas](summary_statistics_example.sas) | captured | 0 | [listing](summary_statistics_example.expected.txt) / [log](summary_statistics_example.oracle.log) | Summary-statistics input, PROC MEANS handoff and two-group TTEST integration |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
