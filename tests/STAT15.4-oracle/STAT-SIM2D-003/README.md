# STAT-SIM2D-003 — SIM2D — COORDINATES / GRID / RESTORE

S154 / Chapter 112 / `COORDINATES Statement` (PDF pp. 9322–9323); S154 / Chapter 112 / `GRID Statement` (PDF pp. 9323–9326); S154 / Chapter 112 / `RESTORE Statement` (PDF pp. 9326–9328).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: SIM2D Procedure; explicit statements: COORDINATES, GRID |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COORDINATES, GRID. Remaining statement variants: RESTORE. Removed an unrelated animal-data fragment sharing the output name SIM. Uses 100 seeded realizations on a 5-by-5 grid instead of the large illustrative simulation.
