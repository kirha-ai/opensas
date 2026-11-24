# STAT-RMSTREG-008 — RMSTREG — LSMEANS / LSMESTIMATE / SLICE

## Source

S154 / Chapter 106 / `LSMEANS Statement` (PDF pp. 8742–8743); S154 / Chapter 106 / `LSMESTIMATE Statement` (PDF pp. 8743–8745); S154 / Chapter 106 / `SLICE Statement` (PDF p. 8747).

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
