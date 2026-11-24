# STAT-LATTICE-001 — LATTICE — Data input, variable roles, and basic options

S154 / Chapter 75 / `PROC LATTICE Statement` (PDF p. 5514); S154 / Chapter 75 / `BY Statement` (PDF pp. 5514–5515); S154 / Chapter 75 / `VAR Statement` (PDF p. 5515); S154 / Chapter 75 / `Input Data Set` (PDF pp. 5515–5516); S154 / Chapter 75 / `Missing Values` (PDF p. 5516).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
