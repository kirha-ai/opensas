# STAT-GLIMMIX-013 — GLIMMIX — Pseudo-likelihood Estimation for Weighted Multilevel Models / GLM Mode or GLMM Mode / Exploring and Comparing Covariance Matrices

## Source

S154 / Chapter 52 / `Pseudo-likelihood Estimation for Weighted Multilevel Models` (PDF pp. 3844–3847); S154 / Chapter 52 / `GLM Mode or GLMM Mode` (PDF pp. 3847–3848); S154 / Chapter 52 / `Exploring and Comparing Covariance Matrices` (PDF pp. 3861–3862).

## Scope

Implement Pseudo-likelihood Estimation for Weighted Multilevel Models; GLM Mode or GLMM Mode; Exploring and Comparing Covariance Matrices. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Pseudo-likelihood Estimation for Weighted Multilevel Models / GLM Mode or GLMM Mode / Exploring and Comparing Covariance Matrices, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.9: Testing Equality of Covariance and Correlation Matrices |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
