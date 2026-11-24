# STAT-BCHOICE-009 — BCHOICE — PREDDIST

## Source

S154 / Chapter 30 / `PREDDIST Statement` (PDF pp. 1195–1196).

## Scope

Implement PREDDIST. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PREDDIST, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [posterior_prediction.sas](posterior_prediction.sas) | captured | 0 | [listing](posterior_prediction.expected.txt) / [log](posterior_prediction.oracle.log) | Explicit PREDDIST and printed posterior predictive draws. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PREDDIST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

**posterior_prediction:** Reduced posterior-prediction fixture with fixed seeds; the sample size is not evidence of MCMC convergence.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
