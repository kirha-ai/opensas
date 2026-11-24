# STAT-SIM2D-009 — SIM2D — Official examples and feature integration regression

## Source

S154 / Chapter 112 / `Examples: SIM2D Procedure` (PDF pp. 9345–9363).

## Scope

Convert this chapter's Examples and Getting Started sections into replayable cases using public data, exercising feature combinations and defaults; explicitly list prerequisites for examples involving other procedures or external products.

## Acceptance criteria

Record inputs, options, expected tables/data sets/graphs, and reference values for every example; pass every example explicitly within this procedure's scope; itemize unmet external prerequisites and link them to tasks; skipped or merely successful runs do not count as numerical validation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SIM2D Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Removed an unrelated animal-data fragment sharing the output name SIM. Uses 100 seeded realizations on a 5-by-5 grid instead of the large illustrative simulation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
