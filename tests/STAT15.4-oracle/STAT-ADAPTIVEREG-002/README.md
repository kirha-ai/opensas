# STAT-ADAPTIVEREG-002 — ADAPTIVEREG — Default adaptive regression spline fitting and prediction

## Source

S154 / Chapter 28 / `Getting Started: ADAPTIVEREG Procedure` (PDF pp. 1047–1054); S154 / Chapter 28 / `Overview: ADAPTIVEREG Procedure` (PDF pp. 1046–1047).

## Scope

Implement default adaptive regression spline fitting and prediction using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Example 28.2: Fitting Data with Mixture Structures |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
