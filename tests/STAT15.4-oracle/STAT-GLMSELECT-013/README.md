# STAT-GLMSELECT-013 — GLMSELECT — CODE / SCORE

S154 / Chapter 56 / `CODE Statement` (PDF p. 4336); S154 / Chapter 56 / `SCORE Statement` (PDF pp. 4355–4356).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: GLMSELECT Procedure |
| [statement_code.sas](statement_code.sas) | [output](statement_code.expected.txt) | [log](statement_code.oracle.log) | 0 | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CODE, SCORE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_code:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
