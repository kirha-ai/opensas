# STAT-KRIGE2D-007 — KRIGE2D — The Pentaspherical Semivariogram Model / The Sine Hole Effect Semivariogram Model / The Power Semivariogram Model

## Source

S154 / Chapter 74 / `The Pentaspherical Semivariogram Model` (PDF p. 5469); S154 / Chapter 74 / `The Sine Hole Effect Semivariogram Model` (PDF pp. 5469–5470); S154 / Chapter 74 / `The Power Semivariogram Model` (PDF pp. 5470–5471).

## Scope

Implement The Pentaspherical Semivariogram Model; The Sine Hole Effect Semivariogram Model; The Power Semivariogram Model. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For The Pentaspherical Semivariogram Model / The Sine Hole Effect Semivariogram Model / The Power Semivariogram Model, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 74.2: Investigating the Effect of Model Specification on Spatial Prediction |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
