# STAT-REG-001 — REG — Data input, variable roles, and basic options

S154 / Chapter 105 / `PROC REG Statement` (PDF pp. 8560–8574); S154 / Chapter 105 / `BY Statement` (PDF pp. 8574–8575); S154 / Chapter 105 / `FREQ Statement` (PDF p. 8576); S154 / Chapter 105 / `ID Statement` (PDF p. 8576); S154 / Chapter 105 / `VAR Statement` (PDF pp. 8599–8600); S154 / Chapter 105 / `WEIGHT Statement` (PDF p. 8600); S154 / Chapter 105 / `Missing Values` (PDF p. 8600); S154 / Chapter 105 / `Input Data Sets` (PDF pp. 8600–8603).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR, WEIGHT. Remaining statement variants: BY, FREQ, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
