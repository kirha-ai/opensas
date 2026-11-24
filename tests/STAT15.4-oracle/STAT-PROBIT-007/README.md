# STAT-PROBIT-007 — PROBIT — ESTIMATE / TEST / Inverse Confidence Limits

S154 / Chapter 100 / `ESTIMATE Statement` (PDF pp. 8109–8110); S154 / Chapter 100 / `TEST Statement` (PDF p. 8120); S154 / Chapter 100 / `Inverse Confidence Limits` (PDF pp. 8127–8128).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Example 100.4: An Epidemiology Study; explicit statements: TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TEST. Remaining statement variants: ESTIMATE. Removed an unrelated PLM fragment that required an absent item store. The epidemic model now explicitly requests ESTIMATE and TEST for dose, plus inverse limits.
