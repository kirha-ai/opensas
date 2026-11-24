# STAT-GLIMMIX-009 — GLIMMIX — Design-Adjusted MBN Estimator / Residual-Based Estimators

## Source

S154 / Chapter 52 / `Design-Adjusted MBN Estimator` (PDF pp. 3859–3861); S154 / Chapter 52 / `Residual-Based Estimators` (PDF pp. 3858–3859).

## Scope

Implement Design-Adjusted MBN Estimator; Residual-Based Estimators. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Design-Adjusted MBN Estimator / Residual-Based Estimators, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.8: Adjusted Covariance Matrices of Fixed Effects |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
