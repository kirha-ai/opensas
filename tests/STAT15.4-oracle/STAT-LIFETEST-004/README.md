# STAT-LIFETEST-004 — LIFETEST — Kernel-Smoothed Hazard Estimate / Comparison of Two or More Groups of Survival Data / Rank Tests for the Association of Survival Time with Covariates

## Source

S154 / Chapter 77 / `Kernel-Smoothed Hazard Estimate` (PDF pp. 5679–5681); S154 / Chapter 77 / `Comparison of Two or More Groups of Survival Data` (PDF pp. 5681–5686); S154 / Chapter 77 / `Rank Tests for the Association of Survival Time with Covariates` (PDF pp. 5686–5687).

## Scope

Implement Kernel-Smoothed Hazard Estimate; Comparison of Two or More Groups of Survival Data; Rank Tests for the Association of Survival Time with Covariates. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Kernel-Smoothed Hazard Estimate / Comparison of Two or More Groups of Survival Data / Rank Tests for the Association of Survival Time with Covariates, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 77.2: Enhanced Survival Plot and Multiple-Comparison Adjustments |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
