# STAT-CAUSALMED-001 — CAUSALMED — Data input, variable roles, and basic options

S154 / Chapter 38 / `PROC CAUSALMED Statement` (PDF pp. 2373–2379); S154 / Chapter 38 / `BY Statement` (PDF pp. 2381–2382); S154 / Chapter 38 / `FREQ Statement` (PDF p. 2388); S154 / Chapter 38 / `WEIGHT Statement` (PDF pp. 2391–2392).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: WEIGHT. Remaining statement variants: BY, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
