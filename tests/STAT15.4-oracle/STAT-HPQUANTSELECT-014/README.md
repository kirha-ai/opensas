# STAT-HPQUANTSELECT-014 — HPQUANTSELECT — Official examples and feature integration regression

## Source

S154 / Chapter 66 / `Examples: HPQUANTSELECT Procedure` (PDF pp. 5012–5018).

## Scope

Convert this chapter's Examples and Getting Started sections into replayable cases using public data, exercising feature combinations and defaults; explicitly list prerequisites for examples involving other procedures or external products.

## Acceptance criteria

Record inputs, options, expected tables/data sets/graphs, and reference values for every example; pass every example explicitly within this procedure's scope; itemize unmet external prerequisites and link them to tasks; skipped or merely successful runs do not count as numerical validation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Official examples and feature integration regression |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
