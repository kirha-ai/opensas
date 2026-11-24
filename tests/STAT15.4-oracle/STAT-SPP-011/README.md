# STAT-SPP-011 — SPP — Likelihood Methods for Model Fitting / Fitted Model Validation That Uses Residuals

## Source

S154 / Chapter 114 / `Likelihood Methods for Model Fitting` (PDF pp. 9420–9421); S154 / Chapter 114 / `Fitted Model Validation That Uses Residuals` (PDF pp. 9421–9423).

## Scope

Implement Likelihood Methods for Model Fitting; Fitted Model Validation That Uses Residuals. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Likelihood Methods for Model Fitting / Fitted Model Validation That Uses Residuals, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SPP Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
