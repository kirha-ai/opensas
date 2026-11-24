# STAT-GLM-007 — GLM — Homogeneity of Variance in One-Way Models / Multivariate Analysis of Variance / Random-Effects Analysis

## Source

S154 / Chapter 53 / `Homogeneity of Variance in One-Way Models` (PDF pp. 4143–4144); S154 / Chapter 53 / `Multivariate Analysis of Variance` (PDF pp. 4147–4149); S154 / Chapter 53 / `Random-Effects Analysis` (PDF pp. 4157–4160).

## Scope

Implement Homogeneity of Variance in One-Way Models; Multivariate Analysis of Variance; Random-Effects Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Homogeneity of Variance in One-Way Models / Multivariate Analysis of Variance / Random-Effects Analysis, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 53.8: Mixed Model Analysis of Variance with the RANDOM Statement |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
