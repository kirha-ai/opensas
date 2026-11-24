# STAT-VARIOGRAM-011 — VARIOGRAM — NLOPTIONS / PARMS / Parameter Initialization

## Source

S154 / Chapter 131 / `NLOPTIONS Statement` (PDF pp. 10794–10795); S154 / Chapter 131 / `PARMS Statement` (PDF pp. 10795–10799); S154 / Chapter 131 / `Parameter Initialization` (PDF pp. 10821–10823).

## Scope

Implement NLOPTIONS; PARMS; Parameter Initialization. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For NLOPTIONS / PARMS / Parameter Initialization, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 131.2: An Anisotropic Case Study with Surface Trend in the Data; explicit statements: PARMS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARMS. Remaining statement variants: NLOPTIONS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
