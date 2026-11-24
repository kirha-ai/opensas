# STAT-QUANTSELECT-005 — QUANTSELECT — Quantile Regression for Extremal Quantile Levels / Backward Elimination (BACKWARD) / LASSO Method (LASSO)

## Source

S154 / Chapter 104 / `Quantile Regression for Extremal Quantile Levels` (PDF pp. 8495–8496); S154 / Chapter 104 / `Backward Elimination (BACKWARD)` (PDF p. 8496); S154 / Chapter 104 / `LASSO Method (LASSO)` (PDF p. 8497).

## Scope

Implement Quantile Regression for Extremal Quantile Levels; Backward Elimination (BACKWARD); LASSO Method (LASSO). This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Quantile Regression for Extremal Quantile Levels / Backward Elimination (BACKWARD) / LASSO Method (LASSO), verify penalty definitions, regularization paths, intercept and standardization handling, and selection criteria; include collinearity and zero coefficients; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: QUANTSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
