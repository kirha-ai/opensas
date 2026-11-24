# STAT-ADAPTIVEREG-001 — ADAPTIVEREG — Data input, variable roles, and basic options

S154 / Chapter 28 / `PROC ADAPTIVEREG Statement` (PDF pp. 1055–1062); S154 / Chapter 28 / `BY Statement` (PDF pp. 1062–1063); S154 / Chapter 28 / `FREQ Statement` (PDF p. 1064); S154 / Chapter 28 / `WEIGHT Statement` (PDF p. 1074); S154 / Chapter 28 / `Missing Values` (PDF pp. 1079–1080).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, WEIGHT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
