# STAT-NLIN-010 — NLIN — CONTRAST / ESTIMATE / Confidence Intervals

## Source

S154 / Chapter 88 / `CONTRAST Statement` (PDF p. 7002); S154 / Chapter 88 / `ESTIMATE Statement` (PDF p. 7003); S154 / Chapter 88 / `Confidence Intervals` (PDF pp. 7034–7035).

## Scope

Implement CONTRAST; ESTIMATE; Confidence Intervals. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / ESTIMATE / Confidence Intervals, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: NLIN Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CONTRAST, ESTIMATE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
