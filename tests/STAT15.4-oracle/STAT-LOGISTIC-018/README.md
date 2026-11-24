# STAT-LOGISTIC-018 — LOGISTIC — CODE / SCORE / Linear Predictor, Predicted Probability, and Confidence Limits

## Source

S154 / Chapter 79 / `CODE Statement` (PDF p. 5855); S154 / Chapter 79 / `SCORE Statement` (PDF pp. 5898–5900); S154 / Chapter 79 / `Linear Predictor, Predicted Probability, and Confidence Limits` (PDF pp. 5925–5926).

## Scope

Implement CODE; SCORE; Linear Predictor, Predicted Probability, and Confidence Limits. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For CODE / SCORE / Linear Predictor, Predicted Probability, and Confidence Limits, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.16: Scoring Data Sets; explicit statements: SCORE |
| [statement_code.sas](statement_code.sas) | captured | 0 | [listing](statement_code.expected.txt) / [log](statement_code.oracle.log) | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SCORE. Remaining statement variants: CODE.

**statement_code:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
