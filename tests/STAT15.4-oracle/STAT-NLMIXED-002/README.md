# STAT-NLMIXED-002 — NLMIXED — Marginal likelihood estimation for nonlinear mixed models

## Source

S154 / Chapter 89 / `Getting Started: NLMIXED Procedure` (PDF pp. 7090–7097); S154 / Chapter 89 / `Overview: NLMIXED Procedure` (PDF pp. 7088–7090).

## Scope

Implement marginal likelihood estimation for nonlinear mixed models using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Example 89.6: Simulated Nested Linear Random-Effects Model |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
