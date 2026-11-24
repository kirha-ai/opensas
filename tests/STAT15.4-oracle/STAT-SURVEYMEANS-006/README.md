# STAT-SURVEYMEANS-006 — SURVEYMEANS — Degrees of Freedom / Coefficient of Variation / Proportions

## Source

S154 / Chapter 121 / `Degrees of Freedom` (PDF pp. 9940–9941); S154 / Chapter 121 / `Coefficient of Variation` (PDF p. 9942); S154 / Chapter 121 / `Proportions` (PDF p. 9942).

## Scope

Implement Degrees of Freedom; Coefficient of Variation; Proportions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Degrees of Freedom / Coefficient of Variation / Proportions, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SURVEYMEANS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
