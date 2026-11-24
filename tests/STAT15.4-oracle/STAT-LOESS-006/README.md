# STAT-LOESS-006 — LOESS — Smoothing Matrix / Model Degrees of Freedom / Statistical Inference and Lookup Degrees of Freedom

## Source

S154 / Chapter 78 / `Smoothing Matrix` (PDF p. 5789); S154 / Chapter 78 / `Model Degrees of Freedom` (PDF pp. 5789–5790); S154 / Chapter 78 / `Statistical Inference and Lookup Degrees of Freedom` (PDF pp. 5790–5791).

## Scope

Implement Smoothing Matrix; Model Degrees of Freedom; Statistical Inference and Lookup Degrees of Freedom. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Smoothing Matrix / Model Degrees of Freedom / Statistical Inference and Lookup Degrees of Freedom, independently verify degrees of freedom and their effects on standard errors, tests, and intervals; cover unbalanced designs and boundary variance estimates; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LOESS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
