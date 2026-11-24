# STAT-REG-004 — REG — ADD / DELETE / PRINT / REFIT / Interactive Analysis

## Source

S154 / Chapter 105 / `ADD Statement` (PDF p. 8574); S154 / Chapter 105 / `DELETE Statement` (PDF pp. 8575–8576); S154 / Chapter 105 / `PRINT Statement` (PDF p. 8592); S154 / Chapter 105 / `REFIT Statement` (PDF pp. 8592–8593); S154 / Chapter 105 / `Interactive Analysis` (PDF pp. 8610–8613).

## Scope

Implement ADD; DELETE; PRINT; REFIT; Interactive Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ADD / DELETE / PRINT / REFIT / Interactive Analysis, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure; explicit statements: ADD, PRINT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ADD, PRINT. Remaining statement variants: DELETE, REFIT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
