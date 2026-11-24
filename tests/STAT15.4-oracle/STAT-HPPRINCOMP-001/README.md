# STAT-HPPRINCOMP-001 — HPPRINCOMP — Data input, variable roles, and basic options

S154 / Chapter 65 / `PROC HPPRINCOMP Statement` (PDF pp. 4950–4954); S154 / Chapter 65 / `BY Statement` (PDF pp. 4954–4955); S154 / Chapter 65 / `FREQ Statement` (PDF pp. 4955–4956); S154 / Chapter 65 / `ID Statement` (PDF p. 4956); S154 / Chapter 65 / `VAR Statement` (PDF p. 4958); S154 / Chapter 65 / `WEIGHT Statement` (PDF p. 4958); S154 / Chapter 65 / `Missing Values` (PDF pp. 4959–4960).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: FREQ, ID, VAR, WEIGHT. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.
