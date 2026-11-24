# STAT-LIFEREG-001 — LIFEREG — Data input, variable roles, and basic options

S154 / Chapter 76 / `PROC LIFEREG Statement` (PDF pp. 5536–5538); S154 / Chapter 76 / `BY Statement` (PDF p. 5548); S154 / Chapter 76 / `WEIGHT Statement` (PDF p. 5566); S154 / Chapter 76 / `Missing Values` (PDF p. 5566).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, WEIGHT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
