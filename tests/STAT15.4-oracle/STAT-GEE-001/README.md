# STAT-GEE-001 — GEE — Data input, variable roles, and basic options

S154 / Chapter 50 / `PROC GEE Statement` (PDF pp. 3426–3428); S154 / Chapter 50 / `BY Statement` (PDF p. 3428); S154 / Chapter 50 / `FREQ Statement` (PDF pp. 3431–3432); S154 / Chapter 50 / `WEIGHT Statement` (PDF p. 3444).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
