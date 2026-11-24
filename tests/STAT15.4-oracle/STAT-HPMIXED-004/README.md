# STAT-HPMIXED-004 — HPMIXED — Model Assumptions / Computing and Maximizing the Likelihood / Sparse Matrix Techniques

## Source

S154 / Chapter 62 / `Model Assumptions` (PDF pp. 4843–4844); S154 / Chapter 62 / `Computing and Maximizing the Likelihood` (PDF pp. 4844–4845); S154 / Chapter 62 / `Sparse Matrix Techniques` (PDF pp. 4846–4847).

## Scope

Implement Model Assumptions; Computing and Maximizing the Likelihood; Sparse Matrix Techniques. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Model Assumptions / Computing and Maximizing the Likelihood / Sparse Matrix Techniques, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 62.2: Comparing Results from PROC HPMIXED and PROC MIXED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
