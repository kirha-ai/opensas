# STAT-PHREG-016 — PHREG — CONTRAST / ESTIMATE / TEST

## Source

S154 / Chapter 92 / `CONTRAST Statement` (PDF pp. 7359–7362); S154 / Chapter 92 / `ESTIMATE Statement` (PDF pp. 7362–7364); S154 / Chapter 92 / `TEST Statement` (PDF pp. 7389–7391).

## Scope

Implement CONTRAST; ESTIMATE; TEST. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / ESTIMATE / TEST, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.3: Modeling with Categorical Predictors; explicit statements: CONTRAST, ESTIMATE, TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CONTRAST, ESTIMATE, TEST. Remaining statement variants: . Restored the official yesno format and the missing terminator of the prior-input DATALINES.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
