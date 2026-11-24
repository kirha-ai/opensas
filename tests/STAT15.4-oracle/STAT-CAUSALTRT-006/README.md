# STAT-CAUSALTRT-006 — CAUSALTRT — BOOTSTRAP

## Source

S154 / Chapter 39 / `BOOTSTRAP Statement` (PDF pp. 2445–2448).

## Scope

Implement BOOTSTRAP. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BOOTSTRAP, verify resampling units, replicate counts, fixed-seed reproducibility, successful replicate counts, and failed-replicate handling; validate intervals/probabilities against enumerated or error-bounded references.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALTRT Procedure |
| [bootstrap_normal.sas](bootstrap_normal.sas) | captured | 0 | [listing](bootstrap_normal.expected.txt) / [log](bootstrap_normal.oracle.log) | Seeded 50-replicate bootstrap with normal confidence intervals. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BOOTSTRAP.

**bootstrap_normal:** A small bootstrap behavior reference; use more replicates for inferential studies.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
