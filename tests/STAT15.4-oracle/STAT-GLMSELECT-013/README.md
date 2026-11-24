# STAT-GLMSELECT-013 — GLMSELECT — CODE / SCORE

## Source

S154 / Chapter 56 / `CODE Statement` (PDF p. 4336); S154 / Chapter 56 / `SCORE Statement` (PDF pp. 4355–4356).

## Scope

Implement CODE; SCORE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For CODE / SCORE, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMSELECT Procedure |
| [statement_code.sas](statement_code.sas) | captured | 0 | [listing](statement_code.expected.txt) / [log](statement_code.oracle.log) | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CODE, SCORE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**statement_code:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
