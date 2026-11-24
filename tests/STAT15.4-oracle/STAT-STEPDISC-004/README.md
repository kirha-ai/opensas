# STAT-STEPDISC-004 — STEPDISC — Computational Resources

## Source

S154 / Chapter 117 / `Computational Resources` (PDF pp. 9566–9567).

## Scope

Implement Computational Resources. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Computational Resources, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: STEPDISC Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
