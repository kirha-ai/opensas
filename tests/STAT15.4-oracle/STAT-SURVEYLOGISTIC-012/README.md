# STAT-SURVEYLOGISTIC-012 — SURVEYLOGISTIC — Bootstrap Method

## Source

S154 / Chapter 120 / `Bootstrap Method` (PDF pp. 9857–9859).

## Scope

Implement Bootstrap Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Bootstrap Method, verify resampling units, replicate counts, fixed-seed reproducibility, successful replicate counts, and failed-replicate handling; validate intervals/probabilities against enumerated or error-bounded references.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
