# STAT-LOGISTIC-017 — LOGISTIC — Model Fitting Information / Regression Diagnostics

## Source

S154 / Chapter 79 / `Model Fitting Information` (PDF pp. 5914–5918); S154 / Chapter 79 / `Regression Diagnostics` (PDF pp. 5938–5941).

## Scope

Implement Model Fitting Information; Regression Diagnostics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Model Fitting Information / Regression Diagnostics, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.6: Logistic Regression Diagnostics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
