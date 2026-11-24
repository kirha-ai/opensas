# STAT-PLM-007 — PLM — LSMEANS / LSMESTIMATE / SLICE

## Source

S154 / Chapter 94 / `LSMEANS Statement` (PDF pp. 7636–7637); S154 / Chapter 94 / `LSMESTIMATE Statement` (PDF pp. 7637–7639); S154 / Chapter 94 / `SLICE Statement` (PDF pp. 7643–7644).

## Scope

Implement LSMEANS; LSMESTIMATE; SLICE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMEANS / LSMESTIMATE / SLICE, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PLM Procedure; explicit statements: LSMEANS, LSMESTIMATE, SLICE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: LSMEANS, LSMESTIMATE, SLICE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
