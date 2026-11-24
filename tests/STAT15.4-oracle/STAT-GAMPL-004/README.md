# STAT-GAMPL-004 — GAMPL — Thin-Plate Regression Splines / Generalized Additive Models / Model Evaluation Criteria

## Source

S154 / Chapter 49 / `Thin-Plate Regression Splines` (PDF pp. 3374–3377); S154 / Chapter 49 / `Generalized Additive Models` (PDF pp. 3377–3379); S154 / Chapter 49 / `Model Evaluation Criteria` (PDF pp. 3379–3380).

## Scope

Implement Thin-Plate Regression Splines; Generalized Additive Models; Model Evaluation Criteria. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Thin-Plate Regression Splines / Generalized Additive Models / Model Evaluation Criteria, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GAMPL Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
