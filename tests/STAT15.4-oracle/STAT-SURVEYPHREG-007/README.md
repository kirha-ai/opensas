# STAT-SURVEYPHREG-007 — SURVEYPHREG — Specifying the Sample Design / Taylor Series Linearization / Balanced Repeated Replication (BRR) Method

## Source

S154 / Chapter 122 / `Specifying the Sample Design` (PDF pp. 10052–10054); S154 / Chapter 122 / `Taylor Series Linearization` (PDF pp. 10057–10058); S154 / Chapter 122 / `Balanced Repeated Replication (BRR) Method` (PDF pp. 10058–10061).

## Scope

Implement Specifying the Sample Design; Taylor Series Linearization; Balanced Repeated Replication (BRR) Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specifying the Sample Design / Taylor Series Linearization / Balanced Repeated Replication (BRR) Method, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
