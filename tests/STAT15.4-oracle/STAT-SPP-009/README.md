# STAT-SPP-009 — SPP — COVTEST / Testing for Complete Spatial Randomness / Confidence Intervals for Summary Statistics

## Source

S154 / Chapter 114 / `COVTEST Statement` (PDF pp. 9398–9399); S154 / Chapter 114 / `Testing for Complete Spatial Randomness` (PDF p. 9410); S154 / Chapter 114 / `Confidence Intervals for Summary Statistics` (PDF p. 9416).

## Scope

Implement COVTEST; Testing for Complete Spatial Randomness; Confidence Intervals for Summary Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For COVTEST / Testing for Complete Spatial Randomness / Confidence Intervals for Summary Statistics, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 114.2: Testing Covariate Dependence of a Point Pattern; explicit statements: COVTEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COVTEST. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
