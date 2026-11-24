# STAT-PLAN-002 — PLAN — Factorial design and randomization plan generation

## Source

S154 / Chapter 93 / `Getting Started: PLAN Procedure` (PDF pp. 7585–7588); S154 / Chapter 93 / `Overview: PLAN Procedure` (PDF pp. 7584–7585).

## Scope

Implement factorial design and randomization plan generation using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: PLAN Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
