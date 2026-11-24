# STAT-PLS-001 — PLS — Data input, variable roles, and basic options

S154 / Chapter 95 / `PROC PLS Statement` (PDF pp. 7686–7693); S154 / Chapter 95 / `BY Statement` (PDF p. 7693); S154 / Chapter 95 / `ID Statement` (PDF p. 7696); S154 / Chapter 95 / `Missing Values` (PDF p. 7704).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
