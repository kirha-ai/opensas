# STAT-CATMOD-001 — CATMOD — Data input, variable roles, and basic options

S154 / Chapter 36 / `PROC CATMOD Statement` (PDF pp. 2191–2192); S154 / Chapter 36 / `BY Statement` (PDF pp. 2192–2193); S154 / Chapter 36 / `POPULATION Statement` (PDF pp. 2208–2211); S154 / Chapter 36 / `WEIGHT Statement` (PDF p. 2220); S154 / Chapter 36 / `Missing Values` (PDF p. 2220); S154 / Chapter 36 / `Input Data Sets` (PDF pp. 2220–2223); S154 / Chapter 36 / `Ordering of Populations and Responses` (PDF pp. 2223–2224).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: POPULATION, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: POPULATION, WEIGHT. Remaining statement variants: BY.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
