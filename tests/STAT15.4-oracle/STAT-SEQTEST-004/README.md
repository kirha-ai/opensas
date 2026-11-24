# STAT-SEQTEST-004 — SEQTEST — Boundary Adjustments for Minimum Error Spending / Boundary Adjustments for Overlapping Lower and Upper beta Boundaries / Stochastic Curtailment

## Source

S154 / Chapter 111 / `Boundary Adjustments for Minimum Error Spending` (PDF p. 9175); S154 / Chapter 111 / `Boundary Adjustments for Overlapping Lower and Upper beta Boundaries` (PDF pp. 9175–9176); S154 / Chapter 111 / `Stochastic Curtailment` (PDF pp. 9176–9178).

## Scope

Implement Boundary Adjustments for Minimum Error Spending; Boundary Adjustments for Overlapping Lower and Upper beta Boundaries; Stochastic Curtailment. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Boundary Adjustments for Minimum Error Spending / Boundary Adjustments for Overlapping Lower and Upper beta Boundaries / Stochastic Curtailment, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
