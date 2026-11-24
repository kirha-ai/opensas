# STAT-GLMSELECT-005 — GLMSELECT — Backward Elimination (BACKWARD) / Least Angle Regression (LAR) / Macro Variables Containing Selected Models

## Source

S154 / Chapter 56 / `Backward Elimination (BACKWARD)` (PDF pp. 4360–4361); S154 / Chapter 56 / `Least Angle Regression (LAR)` (PDF pp. 4362–4363); S154 / Chapter 56 / `Macro Variables Containing Selected Models` (PDF pp. 4372–4374).

## Scope

Implement Backward Elimination (BACKWARD); Least Angle Regression (LAR); Macro Variables Containing Selected Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Backward Elimination (BACKWARD) / Least Angle Regression (LAR) / Macro Variables Containing Selected Models, verify penalty definitions, regularization paths, intercept and standardization handling, and selection criteria; include collinearity and zero coefficients; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
