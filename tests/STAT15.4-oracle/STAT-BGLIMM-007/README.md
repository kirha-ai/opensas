# STAT-BGLIMM-007 — BGLIMM — REPEATED

S154 / Chapter 31 / `REPEATED Statement` (PDF pp. 1305–1308).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 31.4: Repeated Growth Measurements with Group Difference; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Removed an isolated illustrative MODEL statement outside PROC; retained the complete REPEATED models.
