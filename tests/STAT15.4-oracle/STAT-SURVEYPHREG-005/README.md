# STAT-SURVEYPHREG-005 — SURVEYPHREG — Time and CLASS Variable Usage / Partial Likelihood Function for the Cox Model / Counting Process Style of Input

## Source

S154 / Chapter 122 / `Time and CLASS Variable Usage` (PDF pp. 10044–10047); S154 / Chapter 122 / `Partial Likelihood Function for the Cox Model` (PDF pp. 10047–10048); S154 / Chapter 122 / `Counting Process Style of Input` (PDF pp. 10048–10049).

## Scope

Implement Time and CLASS Variable Usage; Partial Likelihood Function for the Cox Model; Counting Process Style of Input. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Time and CLASS Variable Usage / Partial Likelihood Function for the Cox Model / Counting Process Style of Input, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
