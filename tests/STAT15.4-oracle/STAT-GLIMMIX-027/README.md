# STAT-GLIMMIX-027 — GLIMMIX — Programming Statements / User-Defined Link or Variance Function

## Source

S154 / Chapter 52 / `Programming Statements` (PDF pp. 3817–3819); S154 / Chapter 52 / `User-Defined Link or Variance Function` (PDF pp. 3819–3823).

## Scope

Implement Programming Statements; User-Defined Link or Variance Function. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Programming Statements / User-Defined Link or Variance Function, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLIMMIX Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
