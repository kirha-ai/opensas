# STAT-GLMSELECT-003 — GLMSELECT — CLASS / EFFECT / MODEL

S154 / Chapter 56 / `CLASS Statement` (PDF pp. 4332–4336); S154 / Chapter 56 / `EFFECT Statement` (PDF pp. 4336–4337); S154 / Chapter 56 / `MODEL Statement` (PDF pp. 4337–4348).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: GLMSELECT Procedure; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: EFFECT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
