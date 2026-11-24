# STAT-PHREG-011 — PHREG — Proportional Rates/Means Models for Recurrent Events / Analysis of Multivariate Failure Time Data

## Source

S154 / Chapter 92 / `Proportional Rates/Means Models for Recurrent Events` (PDF pp. 7400–7401); S154 / Chapter 92 / `Analysis of Multivariate Failure Time Data` (PDF pp. 7419–7428).

## Scope

Implement Proportional Rates/Means Models for Recurrent Events; Analysis of Multivariate Failure Time Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Proportional Rates/Means Models for Recurrent Events / Analysis of Multivariate Failure Time Data, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.10: Analysis of Recurrent Events Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
