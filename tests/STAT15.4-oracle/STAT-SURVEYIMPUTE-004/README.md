# STAT-SURVEYIMPUTE-004 — SURVEYIMPUTE — Specifying the Sample Design / Random Number Generation / Fully Efficient Fractional Imputation

## Source

S154 / Chapter 119 / `Specifying the Sample Design` (PDF pp. 9721–9723); S154 / Chapter 119 / `Random Number Generation` (PDF pp. 9725–9726); S154 / Chapter 119 / `Fully Efficient Fractional Imputation` (PDF pp. 9726–9730).

## Scope

Implement Specifying the Sample Design; Random Number Generation; Fully Efficient Fractional Imputation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specifying the Sample Design / Random Number Generation / Fully Efficient Fractional Imputation, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 119.3: Fully Efficient Fractional Imputation, Fay's Balanced Repeated Replication, and Domain Analysis |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The example’s external survey input is replaced by 512 seeded synthetic observations, positive analysis weights, four Fay-style replicate weights, and explicit missingness flags.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
