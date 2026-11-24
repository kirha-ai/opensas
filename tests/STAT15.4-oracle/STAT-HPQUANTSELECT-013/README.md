# STAT-HPQUANTSELECT-013 — HPQUANTSELECT — PERFORMANCE

S154 / Chapter 66 / `PERFORMANCE Statement` (PDF pp. 4993–4994).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Seeded synthetic quantile-regression fixture: PERFORMANCE |
| [statement_performance.sas](statement_performance.sas) | [output](statement_performance.expected.txt) | [log](statement_performance.oracle.log) | 0 | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

**statement_performance:** Bounded synthetic case; explicitly executes the targeted statement.
