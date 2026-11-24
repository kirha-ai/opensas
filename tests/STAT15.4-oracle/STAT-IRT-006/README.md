# STAT-IRT-006 — IRT — Notation for the Item Response Theory Model / Assumptions / PROC IRT Contrasted with Other SAS Procedures

## Source

S154 / Chapter 72 / `Notation for the Item Response Theory Model` (PDF pp. 5340–5342); S154 / Chapter 72 / `Assumptions` (PDF p. 5342); S154 / Chapter 72 / `PROC IRT Contrasted with Other SAS Procedures` (PDF pp. 5342–5343).

## Scope

Implement Notation for the Item Response Theory Model; Assumptions; PROC IRT Contrasted with Other SAS Procedures. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Notation for the Item Response Theory Model / Assumptions / PROC IRT Contrasted with Other SAS Procedures, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
