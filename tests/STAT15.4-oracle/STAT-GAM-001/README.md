# STAT-GAM-001 — GAM — Data input, variable roles, and basic options

S154 / Chapter 48 / `PROC GAM Statement` (PDF pp. 3296–3298); S154 / Chapter 48 / `BY Statement` (PDF pp. 3298–3299); S154 / Chapter 48 / `FREQ Statement` (PDF p. 3300); S154 / Chapter 48 / `Missing Values` (PDF p. 3307).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
