# STAT-CORRESP-002 — CORRESP — Default correspondence analysis decomposition and coordinates

## Source

S154 / Chapter 41 / `Getting Started: CORRESP Procedure` (PDF pp. 2577–2579); S154 / Chapter 41 / `Overview: CORRESP Procedure` (PDF pp. 2576–2577).

## Scope

Implement default correspondence analysis decomposition and coordinates using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: CORRESP Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
