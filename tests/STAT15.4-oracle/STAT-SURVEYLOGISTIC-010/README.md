# STAT-SURVEYLOGISTIC-010 — SURVEYLOGISTIC — Jackknife Method / Domain Analysis / Hadamard Matrix

## Source

S154 / Chapter 120 / `Jackknife Method` (PDF pp. 9861–9863); S154 / Chapter 120 / `Domain Analysis` (PDF p. 9863); S154 / Chapter 120 / `Hadamard Matrix` (PDF p. 9863).

## Scope

Implement Jackknife Method; Domain Analysis; Hadamard Matrix. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Jackknife Method / Domain Analysis / Hadamard Matrix, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
