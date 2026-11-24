# STAT-NPAR1WAY-005 — NPAR1WAY — Fligner-Policello Test / Empirical Distribution Function Tests

## Source

S154 / Chapter 90 / `Fligner-Policello Test` (PDF pp. 7244–7246); S154 / Chapter 90 / `Empirical Distribution Function Tests` (PDF pp. 7247–7249).

## Scope

Implement Fligner-Policello Test; Empirical Distribution Function Tests. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Fligner-Policello Test / Empirical Distribution Function Tests, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: NPAR1WAY Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
