# STAT-GLIMMIX-021 — GLIMMIX — LSMEANS / LSMESTIMATE / SLICE

## Source

S154 / Chapter 52 / `LSMEANS Statement` (PDF pp. 3751–3764); S154 / Chapter 52 / `LSMESTIMATE Statement` (PDF pp. 3764–3772); S154 / Chapter 52 / `SLICE Statement` (PDF p. 3817).

## Scope

Implement LSMEANS; LSMESTIMATE; SLICE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMEANS / LSMESTIMATE / SLICE, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.17: Linear Inference Based on Summary Data; explicit statements: LSMEANS, LSMESTIMATE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: LSMEANS, LSMESTIMATE. Remaining statement variants: SLICE. Restored the PDATA construction across the physical PDF page 4026/4027 break.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
