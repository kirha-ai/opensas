# STAT-TPSPLINE-005 — TPSPLINE — SCORE

## Source

S154 / Chapter 125 / `SCORE Statement` (PDF pp. 10307–10308).

## Scope

Implement SCORE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For SCORE, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TPSPLINE Procedure; explicit statements: SCORE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SCORE. Remaining statement variants: . Routes traditional SAS/GRAPH output to a temporary SVG file in the session, allowing independent replay without server-directory write permissions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
