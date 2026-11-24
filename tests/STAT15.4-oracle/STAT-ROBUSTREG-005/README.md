# STAT-ROBUSTREG-005 — ROBUSTREG — Robust Distance / Implementation of the WEIGHT / INEST= Data Set

## Source

S154 / Chapter 107 / `Robust Distance` (PDF pp. 8815–8821); S154 / Chapter 107 / `Implementation of the WEIGHT Statement` (PDF pp. 8822–8823); S154 / Chapter 107 / `INEST= Data Set` (PDF pp. 8823–8824).

## Scope

Implement Robust Distance; Implementation of the WEIGHT; INEST= Data Set. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Robust Distance / Implementation of the WEIGHT / INEST= Data Set, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 107.2: Robust ANOVA |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
