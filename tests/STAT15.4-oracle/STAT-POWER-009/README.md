# STAT-POWER-009 — POWER — Grouped-Number-Lists / Name-Lists / Grouped-Name-Lists

## Source

S154 / Chapter 96 / `Grouped-Number-Lists` (PDF pp. 7850–7852); S154 / Chapter 96 / `Name-Lists` (PDF p. 7852); S154 / Chapter 96 / `Grouped-Name-Lists` (PDF pp. 7852–7853).

## Scope

Implement Grouped-Number-Lists; Name-Lists; Grouped-Name-Lists. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Grouped-Number-Lists / Name-Lists / Grouped-Name-Lists, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: POWER Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
