# STAT-SURVEYLOGISTIC-006 — SURVEYLOGISTIC — Determining Observations for Likelihood Contributions / Convergence Criteria / Generalized Coefficient of Determination

## Source

S154 / Chapter 120 / `Determining Observations for Likelihood Contributions` (PDF pp. 9845–9846); S154 / Chapter 120 / `Convergence Criteria` (PDF p. 9847); S154 / Chapter 120 / `Generalized Coefficient of Determination` (PDF pp. 9849–9850).

## Scope

Implement Determining Observations for Likelihood Contributions; Convergence Criteria; Generalized Coefficient of Determination. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Determining Observations for Likelihood Contributions / Convergence Criteria / Generalized Coefficient of Determination, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
