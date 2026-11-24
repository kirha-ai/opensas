# STAT-DISCRIM-001 — DISCRIM — Data input, variable roles, and basic options

S154 / Chapter 42 / `PROC DISCRIM Statement` (PDF pp. 2652–2660); S154 / Chapter 42 / `BY Statement` (PDF pp. 2660–2661); S154 / Chapter 42 / `CLASS Statement` (PDF p. 2661); S154 / Chapter 42 / `FREQ Statement` (PDF pp. 2661–2662); S154 / Chapter 42 / `ID Statement` (PDF p. 2662); S154 / Chapter 42 / `VAR Statement` (PDF pp. 2663–2664); S154 / Chapter 42 / `WEIGHT Statement` (PDF p. 2664); S154 / Chapter 42 / `Missing Values` (PDF p. 2664); S154 / Chapter 42 / `Input Data Sets` (PDF pp. 2675–2676).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: CLASS |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS. Remaining statement variants: BY, FREQ, ID, VAR, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
