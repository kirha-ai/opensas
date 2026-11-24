# STAT-PHREG-019 — PHREG — Model Fit Statistics / Residuals / Diagnostics Based on Weighted Residuals

## Source

S154 / Chapter 92 / `Model Fit Statistics` (PDF pp. 7428–7429); S154 / Chapter 92 / `Residuals` (PDF pp. 7430–7433); S154 / Chapter 92 / `Diagnostics Based on Weighted Residuals` (PDF pp. 7433–7434).

## Scope

Implement Model Fit Statistics; Residuals; Diagnostics Based on Weighted Residuals. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Model Fit Statistics / Residuals / Diagnostics Based on Weighted Residuals, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PHREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
