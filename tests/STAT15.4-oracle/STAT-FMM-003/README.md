# STAT-FMM-003 — FMM — CLASS / MODEL / PROBMODEL

S154 / Chapter 46 / `CLASS Statement` (PDF p. 2996); S154 / Chapter 46 / `MODEL Statement` (PDF pp. 2997–3005); S154 / Chapter 46 / `PROBMODEL Statement` (PDF pp. 3009–3011).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 46.4: Modeling Multinomial Overdispersion: Town and Country; explicit statements: CLASS, MODEL, PROBMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL, PROBMODEL. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
