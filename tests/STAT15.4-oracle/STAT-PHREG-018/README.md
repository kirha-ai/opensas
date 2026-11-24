# STAT-PHREG-018 — PHREG — LSMEANS / LSMESTIMATE / SLICE

S154 / Chapter 92 / `LSMEANS Statement` (PDF pp. 7367–7368); S154 / Chapter 92 / `LSMESTIMATE Statement` (PDF pp. 7368–7370); S154 / Chapter 92 / `SLICE Statement` (PDF p. 7389).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: PHREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: LSMEANS, LSMESTIMATE, SLICE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
