# STAT-TRANSREG-001 — TRANSREG — Data input, variable roles, and basic options

S154 / Chapter 126 / `PROC TRANSREG Statement` (PDF pp. 10363–10370); S154 / Chapter 126 / `BY Statement` (PDF p. 10370); S154 / Chapter 126 / `FREQ Statement` (PDF pp. 10370–10371); S154 / Chapter 126 / `ID Statement` (PDF p. 10371); S154 / Chapter 126 / `WEIGHT Statement` (PDF p. 10409); S154 / Chapter 126 / `Missing Values` (PDF pp. 10474–10475); S154 / Chapter 126 / `Missing Values, UNTIE, and Hypothesis Tests` (PDF pp. 10475–10476).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, ID, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
