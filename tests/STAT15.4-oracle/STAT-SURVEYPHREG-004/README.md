# STAT-SURVEYPHREG-004 — SURVEYPHREG — DOMAIN / Notation and Estimation / Failure Time Distribution

## Source

S154 / Chapter 122 / `DOMAIN Statement` (PDF pp. 10022–10023); S154 / Chapter 122 / `Notation and Estimation` (PDF pp. 10042–10043); S154 / Chapter 122 / `Failure Time Distribution` (PDF pp. 10043–10044).

## Scope

Implement DOMAIN; Notation and Estimation; Failure Time Distribution. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DOMAIN / Notation and Estimation / Failure Time Distribution, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: DOMAIN.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
