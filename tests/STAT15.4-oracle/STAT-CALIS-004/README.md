# STAT-CALIS-004 — CALIS — COV / MEAN / PCOV / PVAR / STD / VARIANCE

S154 / Chapter 33 / `COV Statement` (PDF pp. 1544–1549); S154 / Chapter 33 / `MEAN Statement` (PDF pp. 1602–1605); S154 / Chapter 33 / `PCOV Statement` (PDF pp. 1638–1641); S154 / Chapter 33 / `PVAR Statement` (PDF pp. 1641–1643); S154 / Chapter 33 / `STD Statement` (PDF p. 1653); S154 / Chapter 33 / `VARIANCE Statement` (PDF pp. 1657–1661).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 33.11: Measurement Error Models Specified as Linear Equations; explicit statements: COV, MEAN, PCOV, PVAR, VARIANCE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COV, MEAN, PCOV, PVAR, VARIANCE. Remaining statement variants: STD. Restored the blank _NAME_ field on the MEAN row and converted the extracted covariance rows to list input.
