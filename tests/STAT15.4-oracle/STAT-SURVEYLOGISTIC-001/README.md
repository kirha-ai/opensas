# STAT-SURVEYLOGISTIC-001 — SURVEYLOGISTIC — Data input, variable roles, and basic options

S154 / Chapter 120 / `PROC SURVEYLOGISTIC Statement` (PDF pp. 9803–9811); S154 / Chapter 120 / `BY Statement` (PDF pp. 9811–9812); S154 / Chapter 120 / `CLUSTER Statement` (PDF p. 9814); S154 / Chapter 120 / `FREQ Statement` (PDF p. 9820); S154 / Chapter 120 / `REPWEIGHTS Statement` (PDF pp. 9834–9836); S154 / Chapter 120 / `STRATA Statement` (PDF p. 9837); S154 / Chapter 120 / `WEIGHT Statement` (PDF p. 9839); S154 / Chapter 120 / `Missing Values` (PDF pp. 9839–9840).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: CLUSTER, STRATA, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLUSTER, STRATA, WEIGHT. Remaining statement variants: BY, FREQ, REPWEIGHTS.
