# STAT-SURVEYREG-005 — SURVEYREG — Notation / Regression Coefficients / Design Effect

## Source

S154 / Chapter 123 / `Notation` (PDF pp. 10144–10145); S154 / Chapter 123 / `Regression Coefficients` (PDF p. 10145); S154 / Chapter 123 / `Design Effect` (PDF pp. 10145–10146).

## Scope

Implement Notation; Regression Coefficients; Design Effect. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Notation / Regression Coefficients / Design Effect, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 123.3: Regression Estimator for Simple Random Sample |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
