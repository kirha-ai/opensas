# STAT-PSMATCH-001 — PSMATCH — Data input, variable roles, and basic options

S154 / Chapter 101 / `PROC PSMATCH Statement` (PDF pp. 8214–8217); S154 / Chapter 101 / `BY Statement` (PDF pp. 8222–8223); S154 / Chapter 101 / `CLASS Statement` (PDF p. 8223); S154 / Chapter 101 / `FREQ Statement` (PDF p. 8223); S154 / Chapter 101 / `ID Statement` (PDF p. 8223); S154 / Chapter 101 / `STRATA Statement` (PDF pp. 8234–8235); S154 / Chapter 101 / `Weighting after Stratification` (PDF pp. 8243–8244); S154 / Chapter 101 / `Weighting after Matching` (PDF pp. 8248–8250).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: CLASS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS. Remaining statement variants: BY, FREQ, ID, STRATA.
