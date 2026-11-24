# STAT-CANCORR-001 — CANCORR — Data input, variable roles, and basic options

S154 / Chapter 34 / `PROC CANCORR Statement` (PDF pp. 2126–2132); S154 / Chapter 34 / `BY Statement` (PDF p. 2132); S154 / Chapter 34 / `FREQ Statement` (PDF pp. 2132–2133); S154 / Chapter 34 / `VAR Statement` (PDF p. 2133); S154 / Chapter 34 / `WEIGHT Statement` (PDF p. 2133); S154 / Chapter 34 / `Missing Values` (PDF p. 2134).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY, FREQ, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
