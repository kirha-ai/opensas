# STAT-PHREG-013 — PHREG — BAYES / Specifics for Bayesian Analysis

S154 / Chapter 92 / `BAYES Statement` (PDF pp. 7341–7355); S154 / Chapter 92 / `Specifics for Bayesian Analysis` (PDF pp. 7455–7466).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 92.14: Bayesian Analysis of Piecewise Exponential Model; explicit statements: BAYES |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BAYES. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
