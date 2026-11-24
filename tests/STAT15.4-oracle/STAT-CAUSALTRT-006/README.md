# STAT-CAUSALTRT-006 — CAUSALTRT — BOOTSTRAP

S154 / Chapter 39 / `BOOTSTRAP Statement` (PDF pp. 2445–2448).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: CAUSALTRT Procedure |
| [bootstrap_normal.sas](bootstrap_normal.sas) | [output](bootstrap_normal.expected.txt) | [log](bootstrap_normal.oracle.log) | 0 | Seeded 50-replicate bootstrap with normal confidence intervals. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BOOTSTRAP.

**bootstrap_normal:** A small bootstrap behavior reference; use more replicates for inferential studies.
