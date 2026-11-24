# STAT-LOESS-004 — LOESS — Data Scaling / Direct versus Interpolated Fitting / k-d Trees and Blending

## Source

S154 / Chapter 78 / `Data Scaling` (PDF pp. 5786–5787); S154 / Chapter 78 / `Direct versus Interpolated Fitting` (PDF p. 5787); S154 / Chapter 78 / `k-d Trees and Blending` (PDF pp. 5787–5788).

## Scope

Implement Data Scaling; Direct versus Interpolated Fitting; k-d Trees and Blending. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Data Scaling / Direct versus Interpolated Fitting / k-d Trees and Blending, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LOESS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
