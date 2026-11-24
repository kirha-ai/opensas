# STAT-QUANTREG-001 — QUANTREG — Data input, variable roles, and basic options

S154 / Chapter 103 / `PROC QUANTREG Statement` (PDF pp. 8372–8378); S154 / Chapter 103 / `BY Statement` (PDF p. 8378); S154 / Chapter 103 / `ID Statement` (PDF pp. 8385–8386); S154 / Chapter 103 / `WEIGHT Statement` (PDF p. 8393).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, ID, WEIGHT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
