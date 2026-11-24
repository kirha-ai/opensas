# STAT-PLM-008 — PLM — CODE / SCORE / Scoring Data Sets for Zero-Inflated Models

## Source

S154 / Chapter 94 / `CODE Statement` (PDF pp. 7632–7633); S154 / Chapter 94 / `SCORE Statement` (PDF pp. 7639–7641); S154 / Chapter 94 / `Scoring Data Sets for Zero-Inflated Models` (PDF p. 7648).

## Scope

Implement CODE; SCORE; Scoring Data Sets for Zero-Inflated Models. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For CODE / SCORE / Scoring Data Sets for Zero-Inflated Models, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 94.1: Scoring with PROC PLM; explicit statements: SCORE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SCORE. Remaining statement variants: CODE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
