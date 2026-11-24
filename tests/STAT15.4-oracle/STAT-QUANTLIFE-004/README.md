# STAT-QUANTLIFE-004 — QUANTLIFE — BASELINE / Notation for Censored Quantile Regression / Kaplan-Meier-Type Estimator for Censored Quantile Regression

## Source

S154 / Chapter 102 / `BASELINE Statement` (PDF p. 8335); S154 / Chapter 102 / `Notation for Censored Quantile Regression` (PDF pp. 8339–8340); S154 / Chapter 102 / `Kaplan-Meier-Type Estimator for Censored Quantile Regression` (PDF p. 8340).

## Scope

Implement BASELINE; Notation for Censored Quantile Regression; Kaplan-Meier-Type Estimator for Censored Quantile Regression. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BASELINE / Notation for Censored Quantile Regression / Kaplan-Meier-Type Estimator for Censored Quantile Regression, use a manually calculable event table to verify risk sets, survival estimates, variances, and intervals; include coincident events/censoring and entirely censored samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BASELINE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
