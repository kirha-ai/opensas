# STAT-GENMOD-021 — GENMOD — FWDLINK / INVLINK / Programming Statements

## Source

S154 / Chapter 51 / `FWDLINK Statement` (PDF p. 3541); S154 / Chapter 51 / `INVLINK Statement` (PDF pp. 3541–3542); S154 / Chapter 51 / `Programming Statements` (PDF pp. 3558–3560).

## Scope

Implement FWDLINK; INVLINK; Programming Statements. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For FWDLINK / INVLINK / Programming Statements, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit FWDLINK, INVLINK statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: FWDLINK, INVLINK.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
