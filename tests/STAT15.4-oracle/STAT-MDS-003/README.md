# STAT-MDS-003 — MDS — INVAR / MATRIX / Formulas

## Source

S154 / Chapter 81 / `INVAR Statement` (PDF p. 6394); S154 / Chapter 81 / `MATRIX Statement` (PDF pp. 6394–6395); S154 / Chapter 81 / `Formulas` (PDF pp. 6395–6397).

## Scope

Implement INVAR; MATRIX; Formulas. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For INVAR / MATRIX / Formulas, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MDS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: INVAR, MATRIX.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
