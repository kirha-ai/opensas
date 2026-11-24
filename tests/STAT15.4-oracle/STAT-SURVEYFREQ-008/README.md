# STAT-SURVEYFREQ-008 — SURVEYFREQ — TABLES / Specifying the Sample Design / Domain Analysis

## Source

S154 / Chapter 118 / `TABLES Statement` (PDF pp. 9602–9626); S154 / Chapter 118 / `Specifying the Sample Design` (PDF pp. 9627–9629); S154 / Chapter 118 / `Domain Analysis` (PDF pp. 9629–9630).

## Scope

Implement TABLES; Specifying the Sample Design; Domain Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TABLES / Specifying the Sample Design / Domain Analysis, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: TABLES |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TABLES. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
