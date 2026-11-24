# STAT-CLUSTER-001 — CLUSTER — Data input, variable roles, and basic options

S154 / Chapter 40 / `PROC CLUSTER Statement` (PDF pp. 2498–2508); S154 / Chapter 40 / `BY Statement` (PDF pp. 2508–2509); S154 / Chapter 40 / `COPY Statement` (PDF p. 2509); S154 / Chapter 40 / `FREQ Statement` (PDF p. 2509); S154 / Chapter 40 / `ID Statement` (PDF pp. 2509–2510); S154 / Chapter 40 / `VAR Statement` (PDF pp. 2510–2511); S154 / Chapter 40 / `Missing Values` (PDF p. 2521).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: ID |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID. Remaining statement variants: BY, COPY, FREQ, VAR.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
