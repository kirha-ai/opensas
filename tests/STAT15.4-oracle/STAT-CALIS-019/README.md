# STAT-CALIS-019 — CALIS — NLOPTIONS / PARAMETERS / Setting Constraints on Parameters

## Source

S154 / Chapter 33 / `NLOPTIONS Statement` (PDF pp. 1610–1611); S154 / Chapter 33 / `PARAMETERS Statement` (PDF pp. 1613–1616); S154 / Chapter 33 / `Setting Constraints on Parameters` (PDF pp. 1729–1734).

## Scope

Implement NLOPTIONS; PARAMETERS; Setting Constraints on Parameters. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For NLOPTIONS / PARAMETERS / Setting Constraints on Parameters, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.31: Linear Relations among Factor Loadings: COSAN Model Specification; explicit statements: PARAMETERS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARAMETERS. Remaining statement variants: NLOPTIONS. Removed a PDF layout blank line inside matrix DATALINES; it was not a covariance observation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
