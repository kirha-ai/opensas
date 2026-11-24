# STAT-VARIOGRAM-007 — VARIOGRAM — Angle Classification / Distance Classification / Bandwidth Restriction

## Source

S154 / Chapter 131 / `Angle Classification` (PDF pp. 10809–10811); S154 / Chapter 131 / `Distance Classification` (PDF pp. 10811–10812); S154 / Chapter 131 / `Bandwidth Restriction` (PDF pp. 10812–10813).

## Scope

Implement Angle Classification; Distance Classification; Bandwidth Restriction. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Angle Classification / Distance Classification / Bandwidth Restriction, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: VARIOGRAM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
