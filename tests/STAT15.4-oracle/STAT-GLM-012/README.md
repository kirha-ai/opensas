# STAT-GLM-012 — GLM — TEST / Hypothesis Testing in PROC GLM

## Source

S154 / Chapter 53 / `TEST Statement` (PDF pp. 4105–4106); S154 / Chapter 53 / `Hypothesis Testing in PROC GLM` (PDF pp. 4115–4120).

## Scope

Implement TEST; Hypothesis Testing in PROC GLM. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TEST / Hypothesis Testing in PROC GLM, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 53.8: Mixed Model Analysis of Variance with the RANDOM Statement; explicit statements: TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TEST. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
