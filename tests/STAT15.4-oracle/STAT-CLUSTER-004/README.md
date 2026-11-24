# STAT-CLUSTER-004 — CLUSTER — Ultrametrics / Algorithms / Ties

## Source

S154 / Chapter 40 / `Ultrametrics` (PDF pp. 2519–2520); S154 / Chapter 40 / `Algorithms` (PDF p. 2520); S154 / Chapter 40 / `Ties` (PDF pp. 2521–2522).

## Scope

Implement Ultrametrics; Algorithms; Ties. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Ultrametrics / Algorithms / Ties, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 40.1: Cluster Analysis of Flying Mileages between 10 American Cities |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
