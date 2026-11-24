# STAT-HPQUANTSELECT-013 — HPQUANTSELECT — PERFORMANCE

## Source

S154 / Chapter 66 / `PERFORMANCE Statement` (PDF pp. 4993–4994).

## Scope

Implement PERFORMANCE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PERFORMANCE, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: PERFORMANCE |
| [statement_performance.sas](statement_performance.sas) | captured | 0 | [listing](statement_performance.expected.txt) / [log](statement_performance.oracle.log) | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

**statement_performance:** Bounded synthetic case; explicitly executes the targeted statement.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
