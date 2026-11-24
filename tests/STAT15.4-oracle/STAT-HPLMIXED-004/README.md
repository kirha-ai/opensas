# STAT-HPLMIXED-004 — HPLMIXED — Matrix Notation / Formulation of the Mixed Model / Estimating Covariance Parameters in the Mixed Model

## Source

S154 / Chapter 60 / `Matrix Notation` (PDF pp. 4718–4719); S154 / Chapter 60 / `Formulation of the Mixed Model` (PDF pp. 4719–4724); S154 / Chapter 60 / `Estimating Covariance Parameters in the Mixed Model` (PDF pp. 4724–4725).

## Scope

Implement Matrix Notation; Formulation of the Mixed Model; Estimating Covariance Parameters in the Mixed Model. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Matrix Notation / Formulation of the Mixed Model / Estimating Covariance Parameters in the Mixed Model, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPLMIXED Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
