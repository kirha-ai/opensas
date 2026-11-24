# STAT-SURVEYREG-001 — SURVEYREG — Data input, variable roles, and basic options

S154 / Chapter 123 / `PROC SURVEYREG Statement` (PDF pp. 10113–10124); S154 / Chapter 123 / `BY Statement` (PDF pp. 10124–10125); S154 / Chapter 123 / `CLUSTER Statement` (PDF pp. 10126–10127); S154 / Chapter 123 / `REPWEIGHTS Statement` (PDF pp. 10137–10139); S154 / Chapter 123 / `STRATA Statement` (PDF p. 10140); S154 / Chapter 123 / `WEIGHT Statement` (PDF pp. 10141–10142); S154 / Chapter 123 / `Missing Values` (PDF pp. 10142–10143).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Verified default procedure context; explicit statements: STRATA, WEIGHT |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 1 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STRATA, WEIGHT. Remaining statement variants: BY, CLUSTER, REPWEIGHTS.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
