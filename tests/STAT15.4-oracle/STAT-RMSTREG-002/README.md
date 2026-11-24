# STAT-RMSTREG-002 — RMSTREG — Restricted mean survival time regression estimation

## Source

S154 / Chapter 106 / `Getting Started: RMSTREG Procedure` (PDF pp. 8731–8735); S154 / Chapter 106 / `Overview: RMSTREG Procedure` (PDF pp. 8730–8731).

## Scope

Implement restricted mean survival time regression estimation using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Small synthetic/public-input default model adapted to the documented Getting Started procedure |

**documented_default:** Input is an explicit synthetic or public SASHELP adaptation, not a claim to reproduce omitted rows in the printed manual.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
