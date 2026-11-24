# STAT-QUANTSELECT-001 — QUANTSELECT — Data input, variable roles, and basic options

S154 / Chapter 104 / `PROC QUANTSELECT Statement` (PDF pp. 8467–8476); S154 / Chapter 104 / `BY Statement` (PDF p. 8476); S154 / Chapter 104 / `WEIGHT Statement` (PDF p. 8491).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
