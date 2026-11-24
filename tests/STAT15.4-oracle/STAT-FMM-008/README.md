# STAT-FMM-008 — FMM — RESTRICT / Random Starting Values

S154 / Chapter 46 / `RESTRICT Statement` (PDF pp. 3013–3015); S154 / Chapter 46 / `Random Starting Values` (PDF pp. 3030–3031).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: FMM Procedure; explicit statements: RESTRICT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RESTRICT. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
