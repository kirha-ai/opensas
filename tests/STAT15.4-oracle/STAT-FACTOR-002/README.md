# STAT-FACTOR-002 — FACTOR — Factor extraction, communalities, and the default factor solution

## Source

S154 / Chapter 44 / `Getting Started: FACTOR Procedure` (PDF pp. 2792–2797); S154 / Chapter 44 / `Overview: FACTOR Procedure` (PDF pp. 2784–2792).

## Scope

Implement factor extraction, communalities, and the default factor solution using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Example 44.1: Principal Component Analysis |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
