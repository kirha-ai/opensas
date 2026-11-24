# STAT-PROBIT-008 — PROBIT — LSMEANS / LSMESTIMATE / SLICE

## Source

S154 / Chapter 100 / `LSMEANS Statement` (PDF pp. 8110–8111); S154 / Chapter 100 / `LSMESTIMATE Statement` (PDF pp. 8111–8112); S154 / Chapter 100 / `SLICE Statement` (PDF p. 8119).

## Scope

Implement LSMEANS; LSMESTIMATE; SLICE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMEANS / LSMESTIMATE / SLICE, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 100.5: Model Postfitting Analysis; explicit statements: SLICE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SLICE. Remaining statement variants: LSMEANS, LSMESTIMATE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
