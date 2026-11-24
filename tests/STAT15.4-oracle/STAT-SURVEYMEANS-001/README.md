# STAT-SURVEYMEANS-001 — SURVEYMEANS — Data input, variable roles, and basic options

S154 / Chapter 121 / `PROC SURVEYMEANS Statement` (PDF pp. 9907–9923); S154 / Chapter 121 / `BY Statement` (PDF pp. 9923–9924); S154 / Chapter 121 / `CLASS Statement` (PDF p. 9924); S154 / Chapter 121 / `CLUSTER Statement` (PDF pp. 9924–9925); S154 / Chapter 121 / `REPWEIGHTS Statement` (PDF pp. 9931–9933); S154 / Chapter 121 / `STRATA Statement` (PDF p. 9933); S154 / Chapter 121 / `VAR Statement` (PDF pp. 9933–9934); S154 / Chapter 121 / `WEIGHT Statement` (PDF p. 9934); S154 / Chapter 121 / `Missing Values` (PDF pp. 9934–9935).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR, WEIGHT. Remaining statement variants: BY, CLASS, CLUSTER, REPWEIGHTS, STRATA.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
