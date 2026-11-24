# STAT-SURVEYMEANS-005 — SURVEYMEANS — Mean / Variance and Standard Error of the Mean / t Test for the Mean

## Source

S154 / Chapter 121 / `Mean` (PDF pp. 9938–9939); S154 / Chapter 121 / `Variance and Standard Error of the Mean` (PDF pp. 9939–9940); S154 / Chapter 121 / `t Test for the Mean` (PDF p. 9940).

## Scope

Implement Mean; Variance and Standard Error of the Mean; t Test for the Mean. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Mean / Variance and Standard Error of the Mean / t Test for the Mean, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SURVEYMEANS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
