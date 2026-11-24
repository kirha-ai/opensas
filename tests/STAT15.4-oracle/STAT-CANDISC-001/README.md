# STAT-CANDISC-001 — CANDISC — Data input, variable roles, and basic options

S154 / Chapter 35 / `PROC CANDISC Statement` (PDF pp. 2156–2159); S154 / Chapter 35 / `BY Statement` (PDF p. 2159); S154 / Chapter 35 / `CLASS Statement` (PDF pp. 2159–2160); S154 / Chapter 35 / `FREQ Statement` (PDF p. 2160); S154 / Chapter 35 / `VAR Statement` (PDF p. 2160); S154 / Chapter 35 / `WEIGHT Statement` (PDF pp. 2160–2161); S154 / Chapter 35 / `Missing Values` (PDF p. 2161); S154 / Chapter 35 / `Input Data Set` (PDF pp. 2162–2163).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: CLASS, VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, VAR, WEIGHT. Remaining statement variants: BY, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
