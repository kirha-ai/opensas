# STAT-PHREG-001 — PHREG — Data input, variable roles, and basic options

S154 / Chapter 92 / `PROC PHREG Statement` (PDF pp. 7324–7333); S154 / Chapter 92 / `BY Statement` (PDF p. 7355); S154 / Chapter 92 / `FREQ Statement` (PDF p. 7364); S154 / Chapter 92 / `ID Statement` (PDF p. 7367); S154 / Chapter 92 / `STRATA Statement` (PDF pp. 7388–7389); S154 / Chapter 92 / `WEIGHT Statement` (PDF p. 7391).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, ID, STRATA, WEIGHT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
