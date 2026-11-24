# STAT-CALIS-026 — CALIS — Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics

## Source

S154 / Chapter 33 / `Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics` (PDF pp. 1789–1793).

## Scope

Implement Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Case-Level Residuals, Outliers, Leverage Observations, and Residual Diagnostics, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.14: Residual Diagnostics and Robust Estimation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The manual abbreviates the raw data with { More Data }; this fixture uses explicit seeded synthetic factor measurements, including one outlier.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
