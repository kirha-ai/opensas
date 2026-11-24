# STAT-TRANSREG-005 — TRANSREG — Simultaneously Fitting Two Regression Functions / Penalized B-Splines / Smoothing Splines

## Source

S154 / Chapter 126 / `Simultaneously Fitting Two Regression Functions` (PDF pp. 10441–10447); S154 / Chapter 126 / `Penalized B-Splines` (PDF pp. 10447–10450); S154 / Chapter 126 / `Smoothing Splines` (PDF pp. 10450–10454).

## Scope

Implement Simultaneously Fitting Two Regression Functions; Penalized B-Splines; Smoothing Splines. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Simultaneously Fitting Two Regression Functions / Penalized B-Splines / Smoothing Splines, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
