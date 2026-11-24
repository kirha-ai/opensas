# STAT-QUANTREG-003 — QUANTREG — CLASS / EFFECT / MODEL

S154 / Chapter 103 / `CLASS Statement` (PDF pp. 8378–8379); S154 / Chapter 103 / `EFFECT Statement` (PDF p. 8384); S154 / Chapter 103 / `MODEL Statement` (PDF pp. 8386–8390).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 103.3: Quantile Regression Analysis of Birth-Weight Data; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: EFFECT. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
