# STAT-GLM-011 — GLM — CONTRAST / ESTIMATE / MANOVA

## Source

S154 / Chapter 53 / `CONTRAST Statement` (PDF pp. 4068–4070); S154 / Chapter 53 / `ESTIMATE Statement` (PDF pp. 4070–4071); S154 / Chapter 53 / `MANOVA Statement` (PDF pp. 4081–4086).

## Scope

Implement CONTRAST; ESTIMATE; MANOVA. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / ESTIMATE / MANOVA, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 53.6: Multivariate Analysis of Variance; explicit statements: CONTRAST, MANOVA |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CONTRAST, MANOVA. Remaining statement variants: ESTIMATE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
