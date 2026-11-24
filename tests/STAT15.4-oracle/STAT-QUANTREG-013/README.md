# STAT-QUANTREG-013 — QUANTREG — Official examples and feature integration regression

S154 / Chapter 103 / `Examples: QUANTREG Procedure` (PDF pp. 8422–8451).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 103.3: Quantile Regression Analysis of Birth-Weight Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
