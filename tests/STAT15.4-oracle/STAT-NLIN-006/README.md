# STAT-NLIN-006 — NLIN — Computational Methods / Covariance Matrix of Parameter Estimates / Convergence Measures

## Source

S154 / Chapter 88 / `Computational Methods` (PDF pp. 7028–7033); S154 / Chapter 88 / `Covariance Matrix of Parameter Estimates` (PDF pp. 7035–7036); S154 / Chapter 88 / `Convergence Measures` (PDF pp. 7036–7037).

## Scope

Implement Computational Methods; Covariance Matrix of Parameter Estimates; Convergence Measures. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Computational Methods / Covariance Matrix of Parameter Estimates / Convergence Measures, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: NLIN Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
