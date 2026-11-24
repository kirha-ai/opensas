# STAT-BGLIMM-006 — BGLIMM — RANDOM / GLMM with Random Effects / Treatment of Subjects in the RANDOM

S154 / Chapter 31 / `RANDOM Statement` (PDF pp. 1294–1305); S154 / Chapter 31 / `GLMM with Random Effects` (PDF pp. 1314–1315); S154 / Chapter 31 / `Treatment of Subjects in the RANDOM Statement` (PDF pp. 1321–1322).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: BGLIMM Procedure; explicit statements: RANDOM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RANDOM. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
