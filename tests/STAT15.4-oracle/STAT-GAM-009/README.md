# STAT-GAM-009 — GAM — SCORE

## Source

S154 / Chapter 48 / `SCORE Statement` (PDF p. 3307).

## Scope

Implement SCORE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For SCORE, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 48.3: Comparing PROC GAM with PROC LOESS; explicit statements: SCORE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SCORE. Remaining statement variants: . Added the Experiment B fitting step described in prose but omitted from the printed program; PredGAMb is now produced explicitly.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
