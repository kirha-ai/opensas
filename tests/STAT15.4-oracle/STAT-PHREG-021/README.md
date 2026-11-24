# STAT-PHREG-021 — PHREG — BASELINE / Survivor Function Estimators

## Source

S154 / Chapter 92 / `BASELINE Statement` (PDF pp. 7334–7341); S154 / Chapter 92 / `Survivor Function Estimators` (PDF pp. 7441–7446).

## Scope

Implement BASELINE; Survivor Function Estimators. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For BASELINE / Survivor Function Estimators, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PHREG Procedure; explicit statements: BASELINE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BASELINE. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
