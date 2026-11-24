# STAT-SURVEYREG-006 — SURVEYREG — Stratum Collapse / Sampling Rate of the Pooled Stratum from Collapse / Analysis of Variance (ANOVA)

## Source

S154 / Chapter 123 / `Stratum Collapse` (PDF p. 10146); S154 / Chapter 123 / `Sampling Rate of the Pooled Stratum from Collapse` (PDF p. 10146); S154 / Chapter 123 / `Analysis of Variance (ANOVA)` (PDF pp. 10146–10147).

## Scope

Implement Stratum Collapse; Sampling Rate of the Pooled Stratum from Collapse; Analysis of Variance (ANOVA). This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Stratum Collapse / Sampling Rate of the Pooled Stratum from Collapse / Analysis of Variance (ANOVA), use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 123.6: Stratum Collapse |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
