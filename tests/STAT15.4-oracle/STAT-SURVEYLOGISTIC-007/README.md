# STAT-SURVEYLOGISTIC-007 — SURVEYLOGISTIC — INEST= Data Set / Specification of Population Totals and Sampling Rates / Primary Sampling Units (PSUs)

## Source

S154 / Chapter 120 / `INEST= Data Set` (PDF p. 9850); S154 / Chapter 120 / `Specification of Population Totals and Sampling Rates` (PDF pp. 9850–9851); S154 / Chapter 120 / `Primary Sampling Units (PSUs)` (PDF p. 9851).

## Scope

Implement INEST= Data Set; Specification of Population Totals and Sampling Rates; Primary Sampling Units (PSUs). This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For INEST= Data Set / Specification of Population Totals and Sampling Rates / Primary Sampling Units (PSUs), use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 120.1: Stratified Sampling |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official Class format from physical PDF page 9883.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
