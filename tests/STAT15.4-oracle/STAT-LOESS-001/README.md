# STAT-LOESS-001 — LOESS — Data input, variable roles, and basic options

S154 / Chapter 78 / `PROC LOESS Statement` (PDF pp. 5770–5775); S154 / Chapter 78 / `BY Statement` (PDF pp. 5775–5776); S154 / Chapter 78 / `ID Statement` (PDF p. 5776); S154 / Chapter 78 / `WEIGHT Statement` (PDF p. 5784); S154 / Chapter 78 / `Missing Values` (PDF pp. 5784–5785).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: ID |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID. Remaining statement variants: BY, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
