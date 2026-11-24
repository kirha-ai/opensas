# STAT-CALIS-027 — CALIS — Latent Variable Scores

## Source

S154 / Chapter 33 / `Latent Variable Scores` (PDF pp. 1793–1796).

## Scope

Implement Latent Variable Scores. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Latent Variable Scores, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.25: Fitting a Latent Growth Curve Model |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
