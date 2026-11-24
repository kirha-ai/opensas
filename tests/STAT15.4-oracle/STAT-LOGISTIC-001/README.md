# STAT-LOGISTIC-001 — LOGISTIC — Data input, variable roles, and basic options

S154 / Chapter 79 / `PROC LOGISTIC Statement` (PDF pp. 5836–5851); S154 / Chapter 79 / `BY Statement` (PDF p. 5851); S154 / Chapter 79 / `FREQ Statement` (PDF p. 5867); S154 / Chapter 79 / `ID Statement` (PDF p. 5867); S154 / Chapter 79 / `STRATA Statement` (PDF pp. 5901–5902); S154 / Chapter 79 / `WEIGHT Statement` (PDF pp. 5904–5905); S154 / Chapter 79 / `Missing Values` (PDF p. 5905).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: FREQ |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: FREQ. Remaining statement variants: BY, ID, STRATA, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
