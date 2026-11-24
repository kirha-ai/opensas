# STAT-STDIZE-002 — STDIZE — Variable standardization and location/scale estimation

## Source

S154 / Chapter 115 / `Getting Started: STDIZE Procedure` (PDF pp. 9448–9455); S154 / Chapter 115 / `Overview: STDIZE Procedure` (PDF p. 9448).

## Scope

Implement variable standardization and location/scale estimation using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Within-group standardization, reported location/scale and transformed values |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
