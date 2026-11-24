# STAT-GLM-013 — GLM — LSMEANS / MEANS / Means versus LS-Means

## Source

S154 / Chapter 53 / `LSMEANS Statement` (PDF pp. 4072–4081); S154 / Chapter 53 / `MEANS Statement` (PDF pp. 4086–4092); S154 / Chapter 53 / `Means versus LS-Means` (PDF pp. 4129–4131).

## Scope

Implement LSMEANS; MEANS; Means versus LS-Means. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LSMEANS / MEANS / Means versus LS-Means, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 53.1: Randomized Complete Blocks with Means Comparisons and Contrasts; explicit statements: MEANS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MEANS. Remaining statement variants: LSMEANS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
