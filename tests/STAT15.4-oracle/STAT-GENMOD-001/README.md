# STAT-GENMOD-001 — GENMOD — Data input, variable roles, and basic options

S154 / Chapter 51 / `PROC GENMOD Statement` (PDF pp. 3509–3514); S154 / Chapter 51 / `BY Statement` (PDF pp. 3525–3526); S154 / Chapter 51 / `FREQ Statement` (PDF p. 3541); S154 / Chapter 51 / `STRATA Statement` (PDF pp. 3565–3567); S154 / Chapter 51 / `WEIGHT Statement` (PDF p. 3567); S154 / Chapter 51 / `Missing Values` (PDF p. 3616).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, STRATA, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
