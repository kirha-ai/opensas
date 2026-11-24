# STAT-KRIGE2D-010 — KRIGE2D — Spatial Random Fields / Ordinary Kriging

## Source

S154 / Chapter 74 / `Spatial Random Fields` (PDF p. 5483); S154 / Chapter 74 / `Ordinary Kriging` (PDF pp. 5483–5486).

## Scope

Implement Spatial Random Fields; Ordinary Kriging. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Spatial Random Fields / Ordinary Kriging, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: KRIGE2D Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
