# STAT-CALIS-018 — CALIS — BOUNDS / LINCON / NLINCON

## Source

S154 / Chapter 33 / `BOUNDS Statement` (PDF pp. 1533–1534); S154 / Chapter 33 / `LINCON Statement` (PDF pp. 1568–1569); S154 / Chapter 33 / `NLINCON Statement` (PDF p. 1610).

## Scope

Implement BOUNDS; LINCON; NLINCON. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For BOUNDS / LINCON / NLINCON, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.32: Ordinal Relations among Factor Loadings; explicit statements: LINCON |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: LINCON. Remaining statement variants: BOUNDS, NLINCON.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
