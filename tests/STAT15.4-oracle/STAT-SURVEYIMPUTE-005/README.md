# STAT-SURVEYIMPUTE-005 — SURVEYIMPUTE — Two-Stage Fully Efficient Fractional Imputation / Fractional Hot-Deck Imputation / Hot-Deck Imputation

S154 / Chapter 119 / `Two-Stage Fully Efficient Fractional Imputation` (PDF pp. 9730–9742); S154 / Chapter 119 / `Fractional Hot-Deck Imputation` (PDF pp. 9742–9754); S154 / Chapter 119 / `Hot-Deck Imputation` (PDF pp. 9754–9756).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 119.3: Fully Efficient Fractional Imputation, Fay's Balanced Repeated Replication, and Domain Analysis |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The example’s external survey input is replaced by 512 seeded synthetic observations, positive analysis weights, four Fay-style replicate weights, and explicit missingness flags.
