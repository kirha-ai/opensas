# STAT-PROBIT-009 — PROBIT — STORE

## Source

S154 / Chapter 100 / `STORE Statement` (PDF pp. 8119–8120).

## Scope

Implement STORE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For STORE, reload in a new session and reproduce the relevant predictions/inference; verify model metadata, class levels, and parameter covariance; explicitly diagnose incompatible stores or requested functions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 100.3: Logistic Regression and Scoring New Data; explicit statements: STORE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STORE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
