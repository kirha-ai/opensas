# STAT-BGLIMM-015 — BGLIMM — Official examples and feature integration regression

S154 / Chapter 31 / `Examples: BGLIMM Procedure` (PDF pp. 1332–1362).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 31.4: Repeated Growth Measurements with Group Difference |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Removed an isolated illustrative MODEL statement outside PROC; retained the complete REPEATED models.
