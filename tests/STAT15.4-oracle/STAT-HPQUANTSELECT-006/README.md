# STAT-HPQUANTSELECT-006 — HPQUANTSELECT — Macro Variables That Contain Selected Effects / Using the Validation ACL as the STOP= Criterion / Using the Validation ACL as the CHOOSE= Criterion

S154 / Chapter 66 / `Macro Variables That Contain Selected Effects` (PDF pp. 5003–5005); S154 / Chapter 66 / `Using the Validation ACL as the STOP= Criterion` (PDF p. 5006); S154 / Chapter 66 / `Using the Validation ACL as the CHOOSE= Criterion` (PDF p. 5006).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Seeded synthetic quantile-regression fixture: Macro Variables That Contain Selected Effects / Using the Validation ACL as the STOP= Criterion / Using the Validation ACL as the CHOOSE= Criterion |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.
