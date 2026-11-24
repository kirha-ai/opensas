# STAT-LOGISTIC-002 — LOGISTIC — Logistic model estimation for categorical responses

## Source

S154 / Chapter 79 / `Getting Started: LOGISTIC Procedure` (PDF pp. 5828–5835); S154 / Chapter 79 / `Overview: LOGISTIC Procedure` (PDF pp. 5825–5828); S154 / Chapter 9 / `Introduction to Categorical Data Analysis Procedures` (PDF pp. 187–198).

## Scope

Implement logistic model estimation for categorical responses using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Getting Started: LOGISTIC Procedure |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
