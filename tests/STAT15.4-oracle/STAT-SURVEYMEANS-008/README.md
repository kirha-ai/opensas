# STAT-SURVEYMEANS-008 — SURVEYMEANS — Ratio / Domain Statistics / Quantiles

## Source

S154 / Chapter 121 / `Ratio` (PDF pp. 9945–9946); S154 / Chapter 121 / `Domain Statistics` (PDF pp. 9946–9949); S154 / Chapter 121 / `Quantiles` (PDF pp. 9949–9956).

## Scope

Implement Ratio; Domain Statistics; Quantiles. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Ratio / Domain Statistics / Quantiles, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 121.6: Comparing Domain Means |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
