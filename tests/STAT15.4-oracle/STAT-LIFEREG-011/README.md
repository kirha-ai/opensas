# STAT-LIFEREG-011 — LIFEREG — STORE

S154 / Chapter 76 / `STORE Statement` (PDF p. 5565).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: LIFEREG Procedure |
| [statement_store.sas](statement_store.sas) | [output](statement_store.expected.txt) | [log](statement_store.oracle.log) | 0 | Save the fitted item store and inspect it through PROC PLM SHOW ALL. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: STORE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_store:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
