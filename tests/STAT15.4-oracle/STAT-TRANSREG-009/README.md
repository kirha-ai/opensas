# STAT-TRANSREG-009 — TRANSREG — Implicit and Explicit Intercepts / Passive Observations / Point Models

## Source

S154 / Chapter 126 / `Implicit and Explicit Intercepts` (PDF p. 10480); S154 / Chapter 126 / `Passive Observations` (PDF p. 10480); S154 / Chapter 126 / `Point Models` (PDF pp. 10480–10481).

## Scope

Implement Implicit and Explicit Intercepts; Passive Observations; Point Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Implicit and Explicit Intercepts / Passive Observations / Point Models, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
