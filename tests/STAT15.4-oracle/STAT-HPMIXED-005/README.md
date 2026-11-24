# STAT-HPMIXED-005 — HPMIXED — NLOPTIONS / PARMS / Computing Starting Values by EM-REML

## Source

S154 / Chapter 62 / `NLOPTIONS Statement` (PDF p. 4829); S154 / Chapter 62 / `PARMS Statement` (PDF pp. 4831–4834); S154 / Chapter 62 / `Computing Starting Values by EM-REML` (PDF pp. 4845–4846).

## Scope

Implement NLOPTIONS; PARMS; Computing Starting Values by EM-REML. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For NLOPTIONS / PARMS / Computing Starting Values by EM-REML, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 62.3: Using PROC GLIMMIX for Further Analysis of PROC HPMIXED Fit; explicit statements: PARMS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARMS. Remaining statement variants: NLOPTIONS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
