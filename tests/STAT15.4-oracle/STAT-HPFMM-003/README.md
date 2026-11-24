# STAT-HPFMM-003 — HPFMM — CLASS / MODEL / PROBMODEL

S154 / Chapter 58 / `CLASS Statement` (PDF p. 4554); S154 / Chapter 58 / `MODEL Statement` (PDF pp. 4555–4563); S154 / Chapter 58 / `PROBMODEL Statement` (PDF pp. 4566–4568).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 58.1: Modeling Mixing Probabilities: All Mice Are Equal, but Some Mice Are More Equal Than Others; explicit statements: CLASS, MODEL, PROBMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL, PROBMODEL. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
