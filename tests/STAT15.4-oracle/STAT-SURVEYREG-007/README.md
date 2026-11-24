# STAT-SURVEYREG-007 — SURVEYREG — Multiple R-Square / Adjusted R-Square / Root Mean Square Errors

## Source

S154 / Chapter 123 / `Multiple R-Square` (PDF p. 10147); S154 / Chapter 123 / `Adjusted R-Square` (PDF p. 10147); S154 / Chapter 123 / `Root Mean Square Errors` (PDF pp. 10147–10148).

## Scope

Implement Multiple R-Square; Adjusted R-Square; Root Mean Square Errors. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Multiple R-Square / Adjusted R-Square / Root Mean Square Errors, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SURVEYREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
