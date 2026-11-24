# STAT-CALIS-011 — CALIS — MSTRUCT / The MSTRUCT Model

## Source

S154 / Chapter 33 / `MSTRUCT Statement` (PDF pp. 1607–1610); S154 / Chapter 33 / `The MSTRUCT Model` (PDF pp. 1712–1714).

## Scope

Implement MSTRUCT; The MSTRUCT Model. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MSTRUCT / The MSTRUCT Model, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CALIS Procedure; explicit statements: MSTRUCT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MSTRUCT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
