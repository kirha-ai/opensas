# STAT-SURVEYPHREG-001 — SURVEYPHREG — Data input, variable roles, and basic options

S154 / Chapter 122 / `PROC SURVEYPHREG Statement` (PDF pp. 10010–10018); S154 / Chapter 122 / `BY Statement` (PDF pp. 10018–10019); S154 / Chapter 122 / `CLUSTER Statement` (PDF pp. 10021–10022); S154 / Chapter 122 / `FREQ Statement` (PDF pp. 10024–10025); S154 / Chapter 122 / `REPWEIGHTS Statement` (PDF pp. 10038–10040); S154 / Chapter 122 / `STRATA Statement` (PDF pp. 10040–10041); S154 / Chapter 122 / `WEIGHT Statement` (PDF pp. 10041–10042); S154 / Chapter 122 / `Missing Values` (PDF pp. 10054–10057).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: CLUSTER, STRATA, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLUSTER, STRATA, WEIGHT. Remaining statement variants: BY, FREQ, REPWEIGHTS.
