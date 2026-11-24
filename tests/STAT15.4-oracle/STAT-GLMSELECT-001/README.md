# STAT-GLMSELECT-001 — GLMSELECT — Data input, variable roles, and basic options

S154 / Chapter 56 / `PROC GLMSELECT Statement` (PDF pp. 4324–4332); S154 / Chapter 56 / `BY Statement` (PDF p. 4332); S154 / Chapter 56 / `FREQ Statement` (PDF p. 4337); S154 / Chapter 56 / `WEIGHT Statement` (PDF pp. 4356–4357).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, WEIGHT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
