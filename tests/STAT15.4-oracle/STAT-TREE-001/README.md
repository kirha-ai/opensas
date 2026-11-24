# STAT-TREE-001 — TREE — Data input, variable roles, and basic options

S154 / Chapter 127 / `PROC TREE Statement` (PDF pp. 10575–10581); S154 / Chapter 127 / `BY Statement` (PDF p. 10581); S154 / Chapter 127 / `COPY Statement` (PDF p. 10581); S154 / Chapter 127 / `FREQ Statement` (PDF pp. 10581–10582); S154 / Chapter 127 / `ID Statement` (PDF p. 10582); S154 / Chapter 127 / `Missing Values` (PDF p. 10583).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, COPY, FREQ, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
