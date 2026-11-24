# STAT-SURVEYIMPUTE-004 — SURVEYIMPUTE — Specifying the Sample Design / Random Number Generation / Fully Efficient Fractional Imputation

S154 / Chapter 119 / `Specifying the Sample Design` (PDF pp. 9721–9723); S154 / Chapter 119 / `Random Number Generation` (PDF pp. 9725–9726); S154 / Chapter 119 / `Fully Efficient Fractional Imputation` (PDF pp. 9726–9730).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 119.3: Fully Efficient Fractional Imputation, Fay's Balanced Repeated Replication, and Domain Analysis |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The example’s external survey input is replaced by 512 seeded synthetic observations, positive analysis weights, four Fay-style replicate weights, and explicit missingness flags.
