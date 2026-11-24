# STAT-SCORE-001 — SCORE — Data input, variable roles, and basic options

S154 / Chapter 109 / `PROC SCORE Statement` (PDF pp. 8908–8909); S154 / Chapter 109 / `BY Statement` (PDF pp. 8909–8910); S154 / Chapter 109 / `ID Statement` (PDF p. 8910); S154 / Chapter 109 / `VAR Statement` (PDF pp. 8910–8911); S154 / Chapter 109 / `Missing Values` (PDF p. 8911).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. Both the DATA= observations and SCORE= coefficient rows have matching BY groups.
