# STAT-NLIN-008 — NLIN — BOUNDS / PARAMETERS

## Source

S154 / Chapter 88 / `BOUNDS Statement` (PDF pp. 7000–7001); S154 / Chapter 88 / `PARAMETERS Statement` (PDF pp. 7008–7011).

## Scope

Implement BOUNDS; PARAMETERS. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For BOUNDS / PARAMETERS, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 88.4: Affecting Curvature through Parameterization; explicit statements: PARAMETERS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARAMETERS. Remaining statement variants: BOUNDS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
