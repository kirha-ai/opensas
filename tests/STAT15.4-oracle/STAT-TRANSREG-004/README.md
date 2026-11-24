# STAT-TRANSREG-004 — TRANSREG — Box-Cox Transformations / Using Splines and Knots / Linear and Nonlinear Regression Functions

## Source

S154 / Chapter 126 / `Box-Cox Transformations` (PDF pp. 10412–10422); S154 / Chapter 126 / `Using Splines and Knots` (PDF pp. 10422–10433); S154 / Chapter 126 / `Linear and Nonlinear Regression Functions` (PDF pp. 10437–10441).

## Scope

Implement Box-Cox Transformations; Using Splines and Knots; Linear and Nonlinear Regression Functions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Box-Cox Transformations / Using Splines and Knots / Linear and Nonlinear Regression Functions, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 126.2: Box-Cox Transformations |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
