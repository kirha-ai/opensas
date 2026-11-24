# STAT-BCHOICE-001 — BCHOICE — Data input, variable roles, and basic options

S154 / Chapter 30 / `PROC BCHOICE Statement` (PDF pp. 1178–1188); S154 / Chapter 30 / `BY Statement` (PDF pp. 1188–1189).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
