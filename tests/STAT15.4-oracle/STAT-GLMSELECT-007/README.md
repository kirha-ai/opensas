# STAT-GLMSELECT-007 — GLMSELECT — MODELAVERAGE / PARTITION / Forward Selection (FORWARD)

S154 / Chapter 56 / `MODELAVERAGE Statement` (PDF pp. 4348–4352); S154 / Chapter 56 / `PARTITION Statement` (PDF pp. 4354–4355); S154 / Chapter 56 / `Forward Selection (FORWARD)` (PDF pp. 4357–4360).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 56.1: Modeling Baseball Salaries Using Performance Statistics; explicit statements: PARTITION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARTITION. Remaining statement variants: MODELAVERAGE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
