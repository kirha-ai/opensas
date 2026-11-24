# STAT-NPAR1WAY-002 — NPAR1WAY — Nonparametric location and distribution comparisons for independent samples

## Source

S154 / Chapter 90 / `Getting Started: NPAR1WAY Procedure` (PDF pp. 7206–7215); S154 / Chapter 90 / `Overview: NPAR1WAY Procedure` (PDF p. 7206).

## Scope

Implement nonparametric location and distribution comparisons for independent samples using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: NPAR1WAY Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
