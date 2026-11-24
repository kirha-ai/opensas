# STAT-HPCANDISC-001 — HPCANDISC — Data input, variable roles, and basic options

S154 / Chapter 57 / `PROC HPCANDISC Statement` (PDF pp. 4483–4487); S154 / Chapter 57 / `BY Statement` (PDF p. 4487); S154 / Chapter 57 / `CLASS Statement` (PDF p. 4487); S154 / Chapter 57 / `FREQ Statement` (PDF pp. 4487–4488); S154 / Chapter 57 / `ID Statement` (PDF p. 4488); S154 / Chapter 57 / `VAR Statement` (PDF p. 4488); S154 / Chapter 57 / `WEIGHT Statement` (PDF pp. 4488–4489); S154 / Chapter 57 / `Missing Values` (PDF p. 4489).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: CLASS, ID, VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, ID, VAR, WEIGHT. Remaining statement variants: BY, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
