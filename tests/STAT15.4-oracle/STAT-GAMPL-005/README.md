# STAT-GAMPL-005 — GAMPL — Fitting Algorithms / Degrees of Freedom / Model Inference

## Source

S154 / Chapter 49 / `Fitting Algorithms` (PDF pp. 3380–3381); S154 / Chapter 49 / `Degrees of Freedom` (PDF pp. 3381–3382); S154 / Chapter 49 / `Model Inference` (PDF pp. 3382–3383).

## Scope

Implement Fitting Algorithms; Degrees of Freedom; Model Inference. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Fitting Algorithms / Degrees of Freedom / Model Inference, independently verify degrees of freedom and their effects on standard errors, tests, and intervals; cover unbalanced designs and boundary variance estimates; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GAMPL Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
