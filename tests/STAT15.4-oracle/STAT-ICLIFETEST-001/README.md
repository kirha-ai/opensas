# STAT-ICLIFETEST-001 — ICLIFETEST — Data input, variable roles, and basic options

S154 / Chapter 69 / `PROC ICLIFETEST Statement` (PDF pp. 5157–5164); S154 / Chapter 69 / `BY Statement` (PDF pp. 5164–5165); S154 / Chapter 69 / `FREQ Statement` (PDF p. 5165); S154 / Chapter 69 / `STRATA Statement` (PDF pp. 5165–5166); S154 / Chapter 69 / `Missing Values` (PDF p. 5184).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: STRATA |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STRATA. Remaining statement variants: BY, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
