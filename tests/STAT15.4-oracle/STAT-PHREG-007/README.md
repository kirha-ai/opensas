# STAT-PHREG-007 — PHREG — Failure Time Distribution / Partial Likelihood Function for the Cox Model / The Multiplicative Hazards Model

S154 / Chapter 92 / `Failure Time Distribution` (PDF pp. 7391–7392); S154 / Chapter 92 / `Partial Likelihood Function for the Cox Model` (PDF pp. 7396–7397); S154 / Chapter 92 / `The Multiplicative Hazards Model` (PDF pp. 7399–7400).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 92.13: Bayesian Analysis of the Cox Model |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored the official yesno format and the missing terminator of the prior-input DATALINES.
