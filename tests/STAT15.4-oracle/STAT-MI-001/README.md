# STAT-MI-001 — MI — Data input, variable roles, and basic options

S154 / Chapter 82 / `PROC MI Statement` (PDF pp. 6425–6429); S154 / Chapter 82 / `BY Statement` (PDF p. 6429); S154 / Chapter 82 / `CLASS Statement` (PDF pp. 6429–6430); S154 / Chapter 82 / `FREQ Statement` (PDF p. 6436); S154 / Chapter 82 / `VAR Statement` (PDF pp. 6448–6449); S154 / Chapter 82 / `EM Algorithm for Data with Missing Values` (PDF pp. 6450–6451); S154 / Chapter 82 / `Missing Data Patterns` (PDF pp. 6452–6453); S154 / Chapter 82 / `Monotone Methods for Data Sets with Monotone Missing Patterns` (PDF pp. 6455–6456); S154 / Chapter 82 / `FCS Methods for Data Sets with Arbitrary Missing Patterns` (PDF pp. 6464–6466); S154 / Chapter 82 / `Input Data Sets` (PDF pp. 6476–6477).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | [output](statement_by.expected.txt) | [log](statement_by.oracle.log) | 0 | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY, CLASS, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
