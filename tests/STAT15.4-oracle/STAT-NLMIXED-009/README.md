# STAT-NLMIXED-009 — NLMIXED — BOUNDS / PARMS / Restricting the Step Length

S154 / Chapter 89 / `BOUNDS Statement` (PDF pp. 7116–7117); S154 / Chapter 89 / `PARMS Statement` (PDF pp. 7122–7123); S154 / Chapter 89 / `Restricting the Step Length` (PDF pp. 7156–7157).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Explicit PARMS starting values and lower BOUNDS on positive variance parameters. |

**documented_feature:** Small seeded synthetic random-intercept model. This fixture directly exercises PARMS and BOUNDS; alternative step-length algorithms still need additional cases.
