# STAT-HPPRINCOMP-002 — HPPRINCOMP — High-performance principal component decomposition

## Source

S154 / Chapter 65 / `Getting Started: HPPRINCOMP Procedure` (PDF pp. 4946–4950); S154 / Chapter 65 / `Overview: HPPRINCOMP Procedure` (PDF pp. 4944–4946).

## Scope

Implement high-performance principal component decomposition using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 1 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: HPPRINCOMP Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
