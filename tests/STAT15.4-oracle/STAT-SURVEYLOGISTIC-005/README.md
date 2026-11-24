# STAT-SURVEYLOGISTIC-005 — SURVEYLOGISTIC — DOMAIN / UNITS / Link Functions and the Corresponding Distributions

## Source

S154 / Chapter 120 / `DOMAIN Statement` (PDF pp. 9817–9818); S154 / Chapter 120 / `UNITS Statement` (PDF pp. 9838–9839); S154 / Chapter 120 / `Link Functions and the Corresponding Distributions` (PDF pp. 9844–9845).

## Scope

Implement DOMAIN; UNITS; Link Functions and the Corresponding Distributions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DOMAIN / UNITS / Link Functions and the Corresponding Distributions, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: DOMAIN, UNITS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
