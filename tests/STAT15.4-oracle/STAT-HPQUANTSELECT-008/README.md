# STAT-HPQUANTSELECT-008 — HPQUANTSELECT — PARTITION / SELECTION

S154 / Chapter 66 / `PARTITION Statement` (PDF p. 4993); S154 / Chapter 66 / `SELECTION Statement` (PDF pp. 4994–4995).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Seeded synthetic quantile-regression fixture: PARTITION / SELECTION |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.
