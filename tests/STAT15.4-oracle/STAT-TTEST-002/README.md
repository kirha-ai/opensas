# STAT-TTEST-002 — TTEST — Default one-sample and group mean tests

## Source

S154 / Chapter 128 / `Getting Started: TTEST Procedure` (PDF pp. 10597–10603); S154 / Chapter 128 / `Overview: TTEST Procedure` (PDF pp. 10596–10597).

## Scope

Implement default one-sample and group mean tests using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [court_default.sas](court_default.sas) | captured | 0 | [listing](court_default.expected.txt) / [log](court_default.oracle.log) | Default one-sample t test from the Getting Started input |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
