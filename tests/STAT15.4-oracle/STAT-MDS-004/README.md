# STAT-MDS-004 — MDS — OUT= Data Set / Normalization of the Estimates / Comparison with Earlier Procedures

## Source

S154 / Chapter 81 / `OUT= Data Set` (PDF pp. 6397–6398); S154 / Chapter 81 / `Normalization of the Estimates` (PDF pp. 6400–6401); S154 / Chapter 81 / `Comparison with Earlier Procedures` (PDF p. 6401).

## Scope

Implement OUT= Data Set; Normalization of the Estimates; Comparison with Earlier Procedures. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For OUT= Data Set / Normalization of the Estimates / Comparison with Earlier Procedures, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MDS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
