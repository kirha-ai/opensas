# STAT-TRANSREG-010 — TRANSREG — Redundancy Analysis / Optimal Scaling / OPSCORE, MONOTONE, UNTIE, and LINEAR Transformations

## Source

S154 / Chapter 126 / `Redundancy Analysis` (PDF pp. 10481–10484); S154 / Chapter 126 / `Optimal Scaling` (PDF pp. 10484–10485); S154 / Chapter 126 / `OPSCORE, MONOTONE, UNTIE, and LINEAR Transformations` (PDF pp. 10485–10486).

## Scope

Implement Redundancy Analysis; Optimal Scaling; OPSCORE, MONOTONE, UNTIE, and LINEAR Transformations. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Redundancy Analysis / Optimal Scaling / OPSCORE, MONOTONE, UNTIE, and LINEAR Transformations, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 126.2: Box-Cox Transformations |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
