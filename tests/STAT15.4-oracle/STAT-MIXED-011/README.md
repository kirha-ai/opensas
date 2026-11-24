# STAT-MIXED-011 — MIXED — LSMESTIMATE

## Source

S154 / Chapter 84 / `LSMESTIMATE Statement` (PDF pp. 6652–6653).

## Scope

Implement LSMESTIMATE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMESTIMATE, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 84.10: Isotonic Contrasts for Ordered Mean Values; explicit statements: LSMESTIMATE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: LSMESTIMATE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
