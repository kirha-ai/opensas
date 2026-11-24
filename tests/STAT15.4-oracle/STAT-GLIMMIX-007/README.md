# STAT-GLIMMIX-007 — GLIMMIX — Maximum Likelihood Estimation Based on Adaptive Quadrature / Aspects Common to Adaptive Quadrature and Laplace Approximation

## Source

S154 / Chapter 52 / `Maximum Likelihood Estimation Based on Adaptive Quadrature` (PDF pp. 3838–3841); S154 / Chapter 52 / `Aspects Common to Adaptive Quadrature and Laplace Approximation` (PDF pp. 3841–3843).

## Scope

Implement Maximum Likelihood Estimation Based on Adaptive Quadrature; Aspects Common to Adaptive Quadrature and Laplace Approximation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Maximum Likelihood Estimation Based on Adaptive Quadrature / Aspects Common to Adaptive Quadrature and Laplace Approximation, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.11: Maximum Likelihood in Proportional Odds Model with Random Effects |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
