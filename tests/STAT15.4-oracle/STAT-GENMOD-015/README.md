# STAT-GENMOD-015 — GENMOD — Residuals / Assessment of Models Based on Aggregates of Residuals / Case Deletion Diagnostic Statistics

## Source

S154 / Chapter 51 / `Residuals` (PDF pp. 3586–3587); S154 / Chapter 51 / `Assessment of Models Based on Aggregates of Residuals` (PDF pp. 3600–3603); S154 / Chapter 51 / `Case Deletion Diagnostic Statistics` (PDF pp. 3603–3607).

## Scope

Implement Residuals; Assessment of Models Based on Aggregates of Residuals; Case Deletion Diagnostic Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Residuals / Assessment of Models Based on Aggregates of Residuals / Case Deletion Diagnostic Statistics, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
