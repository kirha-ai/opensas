# STAT-KRIGE2D-004 — KRIGE2D — COORDINATES / GRID / PREDICT

## Source

S154 / Chapter 74 / `COORDINATES Statement` (PDF p. 5450); S154 / Chapter 74 / `GRID Statement` (PDF pp. 5450–5453); S154 / Chapter 74 / `PREDICT Statement` (PDF pp. 5453–5455).

## Scope

Implement COORDINATES; GRID; PREDICT. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For COORDINATES / GRID / PREDICT, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: KRIGE2D Procedure; explicit statements: COORDINATES, GRID, PREDICT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COORDINATES, GRID, PREDICT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
