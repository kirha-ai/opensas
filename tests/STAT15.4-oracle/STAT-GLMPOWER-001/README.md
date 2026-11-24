# STAT-GLMPOWER-001 — GLMPOWER — Data input, variable roles, and basic options

S154 / Chapter 55 / `PROC GLMPOWER Statement` (PDF pp. 4260–4261); S154 / Chapter 55 / `BY Statement` (PDF pp. 4261–4262); S154 / Chapter 55 / `WEIGHT Statement` (PDF pp. 4280–4281).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: WEIGHT. Remaining statement variants: BY.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
