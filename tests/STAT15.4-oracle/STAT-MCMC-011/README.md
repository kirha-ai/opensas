# STAT-MCMC-011 — MCMC — Spatial Prior / Floating Point Errors and Overflows / Handling Error Messages

S154 / Chapter 80 / `Spatial Prior` (PDF pp. 6230–6232); S154 / Chapter 80 / `Floating Point Errors and Overflows` (PDF pp. 6232–6235); S154 / Chapter 80 / `Handling Error Messages` (PDF pp. 6235–6237).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 80.12: Change Point Models |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
