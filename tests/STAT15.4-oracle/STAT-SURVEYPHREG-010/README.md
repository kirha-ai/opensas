# STAT-SURVEYPHREG-010 — SURVEYPHREG — Contrasts / Hazard Ratios / Hazard Ratios

## Source

S154 / Chapter 122 / `Contrasts` (PDF pp. 10070–10071); S154 / Chapter 122 / `Hazard Ratios` (PDF pp. 10071–10072); S154 / Chapter 122 / `Hazard Ratios` (PDF pp. 10074–10077).

## Scope

Implement Contrasts; Hazard Ratios; Hazard Ratios. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Contrasts / Hazard Ratios / Hazard Ratios, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
