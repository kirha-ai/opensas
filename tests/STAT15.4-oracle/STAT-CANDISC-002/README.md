# STAT-CANDISC-002 — CANDISC — Canonical discriminant analysis between groups

## Source

S154 / Chapter 35 / `Getting Started: CANDISC Procedure` (PDF pp. 2151–2155); S154 / Chapter 35 / `Overview: CANDISC Procedure` (PDF pp. 2150–2151).

## Scope

Implement canonical discriminant analysis between groups using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 1 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: CANDISC Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
