# STAT-HPSPLIT-008 — HPSPLIT — GROW / PARTITION / PRUNE

S154 / Chapter 68 / `GROW Statement` (PDF pp. 5090–5092); S154 / Chapter 68 / `PARTITION Statement` (PDF pp. 5093–5095); S154 / Chapter 68 / `PRUNE Statement` (PDF pp. 5095–5096).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 68.5: Assessing Variable Importance; explicit statements: PRUNE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PRUNE. Remaining statement variants: GROW, PARTITION. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored complete Dopant and Usable labels with list input after PDF column-space loss.
