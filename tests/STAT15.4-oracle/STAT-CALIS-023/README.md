# STAT-CALIS-023 — CALIS — Counting the Degrees of Freedom / FITINDEX / Assessment of Fit

## Source

S154 / Chapter 33 / `Counting the Degrees of Freedom` (PDF pp. 1774–1776); S154 / Chapter 33 / `FITINDEX Statement` (PDF pp. 1561–1565); S154 / Chapter 33 / `Assessment of Fit` (PDF pp. 1776–1789).

## Scope

Implement Counting the Degrees of Freedom; FITINDEX; Assessment of Fit. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Counting the Degrees of Freedom / FITINDEX / Assessment of Fit, independently verify degrees of freedom and their effects on standard errors, tests, and intervals; cover unbalanced designs and boundary variance estimates; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.21: Testing Equality of Two Covariance Matrices Using a Multiple-Group Analysis; explicit statements: FITINDEX |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: FITINDEX. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
