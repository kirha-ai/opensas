# STAT-HPGENSELECT-001 — HPGENSELECT — Data input, variable roles, and basic options

S154 / Chapter 59 / `PROC HPGENSELECT Statement` (PDF pp. 4629–4636); S154 / Chapter 59 / `BY Statement` (PDF p. 4636); S154 / Chapter 59 / `FREQ Statement` (PDF pp. 4637–4638); S154 / Chapter 59 / `ID Statement` (PDF p. 4638); S154 / Chapter 59 / `WEIGHT Statement` (PDF p. 4652); S154 / Chapter 59 / `Missing Values` (PDF pp. 4653–4654).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, ID, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
