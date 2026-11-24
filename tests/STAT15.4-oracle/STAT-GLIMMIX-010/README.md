# STAT-GLIMMIX-010 — GLIMMIX — From Penalized Splines to Mixed Models / Knot Selection

## Source

S154 / Chapter 52 / `From Penalized Splines to Mixed Models` (PDF pp. 3865–3866); S154 / Chapter 52 / `Knot Selection` (PDF pp. 3866–3870).

## Scope

Implement From Penalized Splines to Mixed Models; Knot Selection. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For From Penalized Splines to Mixed Models / Knot Selection, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.15: Comparing Multiple B-Splines |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
