# STAT-LIFETEST-001 — LIFETEST — Data input, variable roles, and basic options

S154 / Chapter 77 / `PROC LIFETEST Statement` (PDF pp. 5650–5662); S154 / Chapter 77 / `BY Statement` (PDF pp. 5662–5663); S154 / Chapter 77 / `FREQ Statement` (PDF p. 5663); S154 / Chapter 77 / `ID Statement` (PDF p. 5663); S154 / Chapter 77 / `STRATA Statement` (PDF pp. 5663–5668); S154 / Chapter 77 / `WEIGHT Statement` (PDF p. 5670); S154 / Chapter 77 / `Missing Values` (PDF pp. 5670–5671).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: STRATA |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STRATA. Remaining statement variants: BY, FREQ, ID, WEIGHT.
