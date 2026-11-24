# STAT-VARIOGRAM-009 — VARIOGRAM — Parameter Estimates / Quality of Fit / Fitting with Matérn Forms

## Source

S154 / Chapter 131 / `Parameter Estimates` (PDF p. 10823); S154 / Chapter 131 / `Quality of Fit` (PDF pp. 10823–10826); S154 / Chapter 131 / `Fitting with Matérn Forms` (PDF pp. 10826–10827).

## Scope

Implement Parameter Estimates; Quality of Fit; Fitting with Matérn Forms. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Parameter Estimates / Quality of Fit / Fitting with Matérn Forms, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 131.1: Aspects of Semivariogram Model Fitting |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
