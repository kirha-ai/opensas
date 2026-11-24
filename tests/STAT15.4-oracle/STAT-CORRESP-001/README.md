# STAT-CORRESP-001 — CORRESP — Data input, variable roles, and basic options

S154 / Chapter 41 / `PROC CORRESP Statement` (PDF pp. 2579–2589); S154 / Chapter 41 / `BY Statement` (PDF pp. 2589–2590); S154 / Chapter 41 / `ID Statement` (PDF p. 2590); S154 / Chapter 41 / `VAR Statement` (PDF p. 2591); S154 / Chapter 41 / `WEIGHT Statement` (PDF pp. 2591–2592); S154 / Chapter 41 / `Input Data Set` (PDF p. 2592); S154 / Chapter 41 / `Missing and Invalid Data` (PDF p. 2601).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: ID, VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID, VAR. Remaining statement variants: BY, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
