# STAT-CLUSTER-003 — CLUSTER — RMSSTD / Clustering Methods / Miscellaneous Formulas

## Source

S154 / Chapter 40 / `RMSSTD Statement` (PDF p. 2510); S154 / Chapter 40 / `Clustering Methods` (PDF pp. 2511–2518); S154 / Chapter 40 / `Miscellaneous Formulas` (PDF pp. 2518–2519).

## Scope

Implement RMSSTD; Clustering Methods; Miscellaneous Formulas. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RMSSTD / Clustering Methods / Miscellaneous Formulas, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 40.1: Cluster Analysis of Flying Mileages between 10 American Cities |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: RMSSTD.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
