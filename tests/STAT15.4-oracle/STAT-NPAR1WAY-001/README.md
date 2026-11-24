# STAT-NPAR1WAY-001 — NPAR1WAY — Data input, variable roles, and basic options

S154 / Chapter 90 / `PROC NPAR1WAY Statement` (PDF pp. 7215–7224); S154 / Chapter 90 / `BY Statement` (PDF p. 7224); S154 / Chapter 90 / `CLASS Statement` (PDF pp. 7224–7225); S154 / Chapter 90 / `FREQ Statement` (PDF pp. 7229–7230); S154 / Chapter 90 / `STRATA Statement` (PDF pp. 7233–7235); S154 / Chapter 90 / `VAR Statement` (PDF p. 7235); S154 / Chapter 90 / `Missing Values` (PDF pp. 7235–7236).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: CLASS, VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, VAR. Remaining statement variants: BY, FREQ, STRATA.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
