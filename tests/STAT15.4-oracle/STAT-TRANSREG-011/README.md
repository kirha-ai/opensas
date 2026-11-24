# STAT-TRANSREG-011 — TRANSREG — SPLINE and MSPLINE Transformations / Specifying the Number of Knots / SPLINE, BSPLINE, and PSPLINE Comparisons

## Source

S154 / Chapter 126 / `SPLINE and MSPLINE Transformations` (PDF pp. 10486–10487); S154 / Chapter 126 / `Specifying the Number of Knots` (PDF pp. 10487–10489); S154 / Chapter 126 / `SPLINE, BSPLINE, and PSPLINE Comparisons` (PDF p. 10489).

## Scope

Implement SPLINE and MSPLINE Transformations; Specifying the Number of Knots; SPLINE, BSPLINE, and PSPLINE Comparisons. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For SPLINE and MSPLINE Transformations / Specifying the Number of Knots / SPLINE, BSPLINE, and PSPLINE Comparisons, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
