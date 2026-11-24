# STAT-SURVEYREG-009 — SURVEYREG — Jackknife Method / Hadamard Matrix / Degrees of Freedom

## Source

S154 / Chapter 123 / `Jackknife Method` (PDF pp. 10153–10155); S154 / Chapter 123 / `Hadamard Matrix` (PDF p. 10155); S154 / Chapter 123 / `Degrees of Freedom` (PDF pp. 10155–10156).

## Scope

Implement Jackknife Method; Hadamard Matrix; Degrees of Freedom. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Jackknife Method / Hadamard Matrix / Degrees of Freedom, use enumerated small populations or independent replicate-weight calculations to verify design-weighted estimates, variances, degrees of freedom, and relevant corrections; cover strata, PSUs, and domain boundaries, keeping sampling weights distinct from frequencies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 123.9: Variance Estimate Using the Jackknife Method |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official grade-specific inverse inclusion weights established earlier in the chapter.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
