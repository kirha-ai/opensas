# STAT-SURVEYMEANS-003 — SURVEYMEANS — DOMAIN / POSTSTRATA / RATIO

## Source

S154 / Chapter 121 / `DOMAIN Statement` (PDF pp. 9925–9927); S154 / Chapter 121 / `POSTSTRATA Statement` (PDF pp. 9927–9929); S154 / Chapter 121 / `RATIO Statement` (PDF pp. 9929–9931).

## Scope

Implement DOMAIN; POSTSTRATA; RATIO. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DOMAIN / POSTSTRATA / RATIO, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 121.6: Comparing Domain Means; explicit statements: DOMAIN |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: DOMAIN. Remaining statement variants: POSTSTRATA, RATIO.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
