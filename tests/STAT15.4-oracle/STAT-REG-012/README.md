# STAT-REG-012 — REG — Collinearity Diagnostics / Model Fit and Diagnostic Statistics / Influence Statistics

## Source

S154 / Chapter 105 / `Collinearity Diagnostics` (PDF pp. 8624–8626); S154 / Chapter 105 / `Model Fit and Diagnostic Statistics` (PDF pp. 8626–8628); S154 / Chapter 105 / `Influence Statistics` (PDF pp. 8628–8636).

## Scope

Implement Collinearity Diagnostics; Model Fit and Diagnostic Statistics; Influence Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Collinearity Diagnostics / Model Fit and Diagnostic Statistics / Influence Statistics, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
