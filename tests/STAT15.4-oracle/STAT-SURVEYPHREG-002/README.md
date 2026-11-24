# STAT-SURVEYPHREG-002 — SURVEYPHREG — Proportional hazards regression for complex survey data

## Source

S154 / Chapter 122 / `Getting Started: SURVEYPHREG Procedure` (PDF pp. 10006–10009); S154 / Chapter 122 / `Overview: SURVEYPHREG Procedure` (PDF pp. 10005–10006).

## Scope

Implement proportional hazards regression for complex survey data using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Small synthetic/public-input default model adapted to the documented Getting Started procedure |

**documented_default:** Input is an explicit synthetic or public SASHELP adaptation, not a claim to reproduce omitted rows in the printed manual.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
