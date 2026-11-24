# STAT-QUANTLIFE-005 — QUANTLIFE — Nelson-Aalen-Type Estimator for Censored Quantile Regression / Relationship of Quantile Function and Survival Function

## Source

S154 / Chapter 102 / `Nelson-Aalen-Type Estimator for Censored Quantile Regression` (PDF pp. 8340–8341); S154 / Chapter 102 / `Relationship of Quantile Function and Survival Function` (PDF pp. 8341–8342).

## Scope

Implement Nelson-Aalen-Type Estimator for Censored Quantile Regression; Relationship of Quantile Function and Survival Function. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Nelson-Aalen-Type Estimator for Censored Quantile Regression / Relationship of Quantile Function and Survival Function, use a manually calculable event table to verify risk sets, survival estimates, variances, and intervals; include coincident events/censoring and entirely censored samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
