# STAT-QUANTREG-009 — QUANTREG — OUTPUT / OUTEST= Data Set

S154 / Chapter 103 / `OUTPUT Statement` (PDF pp. 8390–8391); S154 / Chapter 103 / `OUTEST= Data Set` (PDF pp. 8414–8415).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 103.1: Comparison of Algorithms; explicit statements: OUTPUT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: OUTPUT. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
