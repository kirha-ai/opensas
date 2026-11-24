# STAT-VARCOMP-006 — VARCOMP — Fixed and Random Effects

## Source

S154 / Chapter 130 / `Fixed and Random Effects` (PDF pp. 10733–10734).

## Scope

Implement Fixed and Random Effects. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Fixed and Random Effects, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: VARCOMP Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
