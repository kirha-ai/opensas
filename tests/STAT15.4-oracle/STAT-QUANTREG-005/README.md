# STAT-QUANTREG-005 — QUANTREG — Covariance-Correlation / Linear Test / Estimating Probability Functions by Using the CONDDIST

S154 / Chapter 103 / `Covariance-Correlation` (PDF pp. 8405–8406); S154 / Chapter 103 / `Linear Test` (PDF pp. 8406–8407); S154 / Chapter 103 / `Estimating Probability Functions by Using the CONDDIST Statement` (PDF pp. 8407–8413).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
