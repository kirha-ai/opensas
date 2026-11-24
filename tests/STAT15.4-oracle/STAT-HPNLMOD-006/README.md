# STAT-HPNLMOD-006 — HPNLMOD — BOUNDS / PARAMETERS / RESTRICT

## Source

S154 / Chapter 63 / `BOUNDS Statement` (PDF pp. 4880–4881); S154 / Chapter 63 / `PARAMETERS Statement` (PDF pp. 4882–4885); S154 / Chapter 63 / `RESTRICT Statement` (PDF pp. 4886–4887).

## Scope

Implement BOUNDS; PARAMETERS; RESTRICT. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For BOUNDS / PARAMETERS / RESTRICT, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPNLMOD Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BOUNDS, PARAMETERS, RESTRICT. Aligned the enzyme input names with the nonlinear model and used stable nonzero starting values.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
