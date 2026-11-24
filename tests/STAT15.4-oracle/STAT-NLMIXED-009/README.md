# STAT-NLMIXED-009 — NLMIXED — BOUNDS / PARMS / Restricting the Step Length

## Source

S154 / Chapter 89 / `BOUNDS Statement` (PDF pp. 7116–7117); S154 / Chapter 89 / `PARMS Statement` (PDF pp. 7122–7123); S154 / Chapter 89 / `Restricting the Step Length` (PDF pp. 7156–7157).

## Scope

Implement BOUNDS; PARMS; Restricting the Step Length. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For BOUNDS / PARMS / Restricting the Step Length, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Explicit PARMS starting values and lower BOUNDS on positive variance parameters. |

**documented_feature:** Small seeded synthetic random-intercept model. This fixture directly exercises PARMS and BOUNDS; alternative step-length algorithms still need additional cases.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
