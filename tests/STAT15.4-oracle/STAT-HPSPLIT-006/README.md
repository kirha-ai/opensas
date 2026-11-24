# STAT-HPSPLIT-006 — HPSPLIT — Primary and Surrogate Splitting Rules / Unknown Values of Categorical Predictors / Variable Importance

S154 / Chapter 68 / `Primary and Surrogate Splitting Rules` (PDF pp. 5108–5109); S154 / Chapter 68 / `Unknown Values of Categorical Predictors` (PDF p. 5110); S154 / Chapter 68 / `Variable Importance` (PDF pp. 5115–5116).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 68.5: Assessing Variable Importance |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored complete Dopant and Usable labels with list input after PDF column-space loss.
