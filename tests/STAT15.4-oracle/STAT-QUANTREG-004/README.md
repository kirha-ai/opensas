# STAT-QUANTREG-004 — QUANTREG — CONDDIST / Quantile Regression as an Optimization Problem / Optimization Algorithms

S154 / Chapter 103 / `CONDDIST Statement` (PDF pp. 8379–8384); S154 / Chapter 103 / `Quantile Regression as an Optimization Problem` (PDF pp. 8393–8394); S154 / Chapter 103 / `Optimization Algorithms` (PDF pp. 8394–8402).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 103.3: Quantile Regression Analysis of Birth-Weight Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CONDDIST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
