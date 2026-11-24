# STAT-MCMC-017 — MCMC — PREDDIST

S154 / Chapter 80 / `PREDDIST Statement` (PDF pp. 6133–6134).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: MCMC Procedure |
| [posterior_prediction.sas](posterior_prediction.sas) | [output](posterior_prediction.expected.txt) | [log](posterior_prediction.oracle.log) | 0 | Explicit PREDDIST and printed posterior predictive draws. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PREDDIST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**posterior_prediction:** Reduced posterior-prediction fixture with fixed seeds; the sample size is not evidence of MCMC convergence.
