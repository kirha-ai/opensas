# STAT-SURVEYREG-004 — SURVEYREG — DOMAIN / Survey Design Information / Primary Sampling Units (PSUs)

## Source

S154 / Chapter 123 / `DOMAIN Statement` (PDF pp. 10128–10130); S154 / Chapter 123 / `Survey Design Information` (PDF pp. 10143–10144); S154 / Chapter 123 / `Primary Sampling Units (PSUs)` (PDF p. 10144).

## Scope

Implement DOMAIN; Survey Design Information; Primary Sampling Units (PSUs). This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DOMAIN / Survey Design Information / Primary Sampling Units (PSUs), use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 123.8: Comparing Domain Statistics; explicit statements: DOMAIN |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: DOMAIN. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
