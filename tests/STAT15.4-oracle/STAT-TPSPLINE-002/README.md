# STAT-TPSPLINE-002 — TPSPLINE — Thin-plate smoothing spline estimation

## Source

S154 / Chapter 125 / `Getting Started: TPSPLINE Procedure` (PDF pp. 10288–10297); S154 / Chapter 125 / `Overview: TPSPLINE Procedure` (PDF pp. 10286–10288).

## Scope

Implement thin-plate smoothing spline estimation using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Thin-plate smoothing, smoothing parameter search and output predictions/limits |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
