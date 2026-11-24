# STAT-GENMOD-014 — GENMOD — LSMEANS / LSMESTIMATE / SLICE

## Source

S154 / Chapter 51 / `LSMEANS Statement` (PDF pp. 3542–3543); S154 / Chapter 51 / `LSMESTIMATE Statement` (PDF pp. 3543–3544); S154 / Chapter 51 / `SLICE Statement` (PDF p. 3565).

## Scope

Implement LSMEANS; LSMESTIMATE; SLICE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMEANS / LSMESTIMATE / SLICE, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: LSMEANS, LSMESTIMATE, SLICE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
