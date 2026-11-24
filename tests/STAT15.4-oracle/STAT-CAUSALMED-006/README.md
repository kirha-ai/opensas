# STAT-CAUSALMED-006 — CAUSALMED — BOOTSTRAP / Bootstrap Methods

S154 / Chapter 38 / `BOOTSTRAP Statement` (PDF pp. 2379–2381); S154 / Chapter 38 / `Bootstrap Methods` (PDF pp. 2406–2407).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [bootstrap_normal.sas](bootstrap_normal.sas) | [output](bootstrap_normal.expected.txt) | [log](bootstrap_normal.oracle.log) | 0 | Seeded 50-replicate bootstrap with normal confidence intervals. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BOOTSTRAP.

**bootstrap_normal:** A small bootstrap behavior reference; use more replicates for inferential studies.
