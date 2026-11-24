# STAT-SURVEYPHREG-006 — SURVEYPHREG — Left-Truncation of Failure Times / The Multiplicative Hazards Model / Firth's Modification for Maximum Likelihood Estimation

## Source

S154 / Chapter 122 / `Left-Truncation of Failure Times` (PDF p. 10049); S154 / Chapter 122 / `The Multiplicative Hazards Model` (PDF pp. 10049–10050); S154 / Chapter 122 / `Firth's Modification for Maximum Likelihood Estimation` (PDF pp. 10050–10052).

## Scope

Implement Left-Truncation of Failure Times; The Multiplicative Hazards Model; Firth's Modification for Maximum Likelihood Estimation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Left-Truncation of Failure Times / The Multiplicative Hazards Model / Firth's Modification for Maximum Likelihood Estimation, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
