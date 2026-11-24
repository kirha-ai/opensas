# STAT-SURVEYPHREG-009 — SURVEYPHREG — Variance Adjustment Factors / Variance Ratios and Standard Error Ratios / Domain Analysis

## Source

S154 / Chapter 122 / `Variance Adjustment Factors` (PDF pp. 10066–10067); S154 / Chapter 122 / `Variance Ratios and Standard Error Ratios` (PDF pp. 10067–10068); S154 / Chapter 122 / `Domain Analysis` (PDF pp. 10068–10069).

## Scope

Implement Variance Adjustment Factors; Variance Ratios and Standard Error Ratios; Domain Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Variance Adjustment Factors / Variance Ratios and Standard Error Ratios / Domain Analysis, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
