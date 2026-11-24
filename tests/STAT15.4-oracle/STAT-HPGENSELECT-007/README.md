# STAT-HPGENSELECT-007 — HPGENSELECT — PARTITION / SELECTION / The LASSO Method of Model Selection

S154 / Chapter 59 / `PARTITION Statement` (PDF pp. 4647–4648); S154 / Chapter 59 / `SELECTION Statement` (PDF pp. 4650–4652); S154 / Chapter 59 / `The LASSO Method of Model Selection` (PDF pp. 4663–4666).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 59.4: Model Selection by the LASSO Method; explicit statements: SELECTION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SELECTION. Remaining statement variants: PARTITION. Reduced the million-row performance illustration to 1,500 rows and 15 candidate covariates for a bounded LASSO fixture.
