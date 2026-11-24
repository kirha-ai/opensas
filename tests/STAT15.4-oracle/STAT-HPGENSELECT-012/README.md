# STAT-HPGENSELECT-012 — HPGENSELECT — PERFORMANCE / Computational Method: Multithreading

## Source

S154 / Chapter 59 / `PERFORMANCE Statement` (PDF p. 4648); S154 / Chapter 59 / `Computational Method: Multithreading` (PDF pp. 4667–4668).

## Scope

Implement PERFORMANCE; Computational Method: Multithreading. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PERFORMANCE / Computational Method: Multithreading, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 59.4: Model Selection by the LASSO Method; explicit statements: PERFORMANCE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PERFORMANCE. Remaining statement variants: . Reduced the million-row performance illustration to 1,500 rows and 15 candidate covariates for a bounded LASSO fixture.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
