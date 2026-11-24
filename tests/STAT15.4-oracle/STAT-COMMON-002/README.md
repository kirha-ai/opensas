# STAT-COMMON-002 — Statistical data selection, missing values, and observation weight interfaces

## Source

S154 / Chapter 13 / `Introduction to Scoring, Standardization, and Ranking Procedures` (PDF pp. 253–254); S154 / Chapter 22 / `FREQ Statement` (PDF p. 564); S154 / Chapter 22 / `ID Statement` (PDF p. 564); S154 / Chapter 22 / `VAR Statement` (PDF p. 570); S154 / Chapter 22 / `WEIGHT Statement` (PDF p. 570).

## Scope

Provide shared data access interfaces for BY, variable roles, FREQ, WEIGHT, ID, and missing-value filtering; individual procedures determine exclusion granularity, weight meaning, and invalid-value behavior rather than imposing one global policy.

## Acceptance criteria

Use multiple groups to verify traceability of original row numbers, variable types, and missing indicators; keep frequency and analysis weights separate in the interface; PROC-specific filtering policies must not modify the original data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [weight_roles.sas](weight_roles.sas) | captured | 0 | [listing](weight_roles.expected.txt) / [log](weight_roles.oracle.log) | BY selection and the distinct frequency/analysis weight roles |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
