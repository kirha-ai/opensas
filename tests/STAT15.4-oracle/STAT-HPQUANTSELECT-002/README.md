# STAT-HPQUANTSELECT-002 — HPQUANTSELECT — High-performance quantile regression and model selection

## Source

S154 / Chapter 66 / `Getting Started: HPQUANTSELECT Procedure` (PDF pp. 4976–4985); S154 / Chapter 66 / `Overview: HPQUANTSELECT Procedure` (PDF pp. 4972–4976).

## Scope

Implement high-performance quantile regression and model selection using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Seeded synthetic quantile-regression fixture: High-performance quantile regression and model selection |

**documented_default:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
