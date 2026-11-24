# STAT-CALIS-010 — CALIS — LISMOD / The LISMOD Model and Submodels

## Source

S154 / Chapter 33 / `LISMOD Statement` (PDF pp. 1575–1579); S154 / Chapter 33 / `The LISMOD Model and Submodels` (PDF pp. 1703–1712).

## Scope

Implement LISMOD; The LISMOD Model and Submodels. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LISMOD / The LISMOD Model and Submodels, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CALIS Procedure; explicit statements: LISMOD |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: LISMOD. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
