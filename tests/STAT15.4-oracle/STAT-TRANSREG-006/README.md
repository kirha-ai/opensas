# STAT-TRANSREG-006 — TRANSREG — Smoothing Splines Changes and Enhancements / Iteration History Changes and Enhancements / ANOVA Codings

## Source

S154 / Chapter 126 / `Smoothing Splines Changes and Enhancements` (PDF pp. 10454–10456); S154 / Chapter 126 / `Iteration History Changes and Enhancements` (PDF pp. 10456–10457); S154 / Chapter 126 / `ANOVA Codings` (PDF pp. 10457–10474).

## Scope

Implement Smoothing Splines Changes and Enhancements; Iteration History Changes and Enhancements; ANOVA Codings. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Smoothing Splines Changes and Enhancements / Iteration History Changes and Enhancements / ANOVA Codings, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
