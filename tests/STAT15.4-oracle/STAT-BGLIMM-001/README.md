# STAT-BGLIMM-001 — BGLIMM — Data input, variable roles, and basic options

S154 / Chapter 31 / `PROC BGLIMM Statement` (PDF pp. 1275–1283); S154 / Chapter 31 / `BY Statement` (PDF pp. 1283–1284); S154 / Chapter 31 / `Models with Missing Values` (PDF p. 1315); S154 / Chapter 31 / `Missing Data` (PDF p. 1323).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
