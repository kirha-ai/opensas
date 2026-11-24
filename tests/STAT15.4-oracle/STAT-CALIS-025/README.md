# STAT-CALIS-025 — CALIS — SIMTESTS / TESTFUNC / Gradient, Hessian, Information Matrix, and Approximate Standard Errors

## Source

S154 / Chapter 33 / `SIMTESTS Statement` (PDF pp. 1652–1653); S154 / Chapter 33 / `TESTFUNC Statement` (PDF pp. 1653–1654); S154 / Chapter 33 / `Gradient, Hessian, Information Matrix, and Approximate Standard Errors` (PDF pp. 1770–1774).

## Scope

Implement SIMTESTS; TESTFUNC; Gradient, Hessian, Information Matrix, and Approximate Standard Errors. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For SIMTESTS / TESTFUNC / Gradient, Hessian, Information Matrix, and Approximate Standard Errors, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.28: Multiple-Group Model for Purchasing Behavior; explicit statements: SIMTESTS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SIMTESTS. Remaining statement variants: TESTFUNC. Removed a trailing incomplete RAM illustration; the complete multiple-group SIMTESTS models remain.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
