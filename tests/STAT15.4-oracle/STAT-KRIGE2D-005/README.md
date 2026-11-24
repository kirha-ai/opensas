# STAT-KRIGE2D-005 — KRIGE2D — RESTORE / The Gaussian Semivariogram Model / The Exponential Semivariogram Model

## Source

S154 / Chapter 74 / `RESTORE Statement` (PDF pp. 5463–5465); S154 / Chapter 74 / `The Gaussian Semivariogram Model` (PDF p. 5466); S154 / Chapter 74 / `The Exponential Semivariogram Model` (PDF pp. 5466–5467).

## Scope

Implement RESTORE; The Gaussian Semivariogram Model; The Exponential Semivariogram Model. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RESTORE / The Gaussian Semivariogram Model / The Exponential Semivariogram Model, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 74.2: Investigating the Effect of Model Specification on Spatial Prediction; explicit statements: RESTORE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RESTORE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
