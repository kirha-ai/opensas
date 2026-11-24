# STAT-TRANSREG-017 — TRANSREG — Scoring Spline Variables

## Source

S154 / Chapter 126 / `Scoring Spline Variables` (PDF pp. 10433–10437).

## Scope

Implement Scoring Spline Variables. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Scoring Spline Variables, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
