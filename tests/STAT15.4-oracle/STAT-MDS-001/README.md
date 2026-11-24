# STAT-MDS-001 — MDS — Data input, variable roles, and basic options

S154 / Chapter 81 / `PROC MDS Statement` (PDF pp. 6383–6393); S154 / Chapter 81 / `BY Statement` (PDF pp. 6393–6394); S154 / Chapter 81 / `ID Statement` (PDF p. 6394); S154 / Chapter 81 / `VAR Statement` (PDF p. 6395); S154 / Chapter 81 / `WEIGHT Statement` (PDF p. 6395); S154 / Chapter 81 / `Missing Values` (PDF p. 6400).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: ID |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID. Remaining statement variants: BY, VAR, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
