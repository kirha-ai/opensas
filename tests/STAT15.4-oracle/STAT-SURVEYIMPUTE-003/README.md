# STAT-SURVEYIMPUTE-003 — SURVEYIMPUTE — CELLS / IMPJOINT / Definitions

S154 / Chapter 119 / `CELLS Statement` (PDF p. 9714); S154 / Chapter 119 / `IMPJOINT Statement` (PDF p. 9716); S154 / Chapter 119 / `Definitions` (PDF pp. 9720–9721).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 119.3: Fully Efficient Fractional Imputation, Fay's Balanced Repeated Replication, and Domain Analysis; explicit statements: CELLS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CELLS. Remaining statement variants: IMPJOINT. The example’s external survey input is replaced by 512 seeded synthetic observations, positive analysis weights, four Fay-style replicate weights, and explicit missingness flags.
