# STAT-FACTOR-001 — FACTOR — Data input, variable roles, and basic options

S154 / Chapter 44 / `PROC FACTOR Statement` (PDF pp. 2797–2816); S154 / Chapter 44 / `BY Statement` (PDF p. 2816); S154 / Chapter 44 / `FREQ Statement` (PDF pp. 2816–2817); S154 / Chapter 44 / `VAR Statement` (PDF p. 2823); S154 / Chapter 44 / `WEIGHT Statement` (PDF pp. 2823–2824); S154 / Chapter 44 / `Input Data Set` (PDF pp. 2824–2826); S154 / Chapter 44 / `Missing Values` (PDF pp. 2834–2835).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY, FREQ, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
