# STAT-DISTANCE-001 — DISTANCE — Data input, variable roles, and basic options

S154 / Chapter 43 / `PROC DISTANCE Statement` (PDF pp. 2747–2754); S154 / Chapter 43 / `VAR Statement` (PDF pp. 2754–2759); S154 / Chapter 43 / `ID Statement` (PDF p. 2759); S154 / Chapter 43 / `COPY Statement` (PDF p. 2759); S154 / Chapter 43 / `BY Statement` (PDF pp. 2759–2760); S154 / Chapter 43 / `FREQ Statement` (PDF p. 2760); S154 / Chapter 43 / `WEIGHT Statement` (PDF pp. 2760–2761); S154 / Chapter 43 / `Missing Values` (PDF p. 2768); S154 / Chapter 43 / `Formatted versus Unformatted Values` (PDF pp. 2768–2769).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR, FREQ, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR, FREQ, WEIGHT. Remaining statement variants: ID, COPY, BY.
