# STAT-GLMSELECT-010 — GLMSELECT — Criteria Used in Model Selection Methods / Model Averaging / Using Validation and Test Data

## Source

S154 / Chapter 56 / `Criteria Used in Model Selection Methods` (PDF pp. 4368–4370); S154 / Chapter 56 / `Model Averaging` (PDF pp. 4376–4377); S154 / Chapter 56 / `Using Validation and Test Data` (PDF pp. 4377–4379).

## Scope

Implement Criteria Used in Model Selection Methods; Model Averaging; Using Validation and Test Data. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Criteria Used in Model Selection Methods / Model Averaging / Using Validation and Test Data, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
