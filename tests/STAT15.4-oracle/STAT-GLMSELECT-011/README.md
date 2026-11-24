# STAT-GLMSELECT-011 — GLMSELECT — Cross Validation / External Cross Validation / Screening

## Source

S154 / Chapter 56 / `Cross Validation` (PDF pp. 4379–4381); S154 / Chapter 56 / `External Cross Validation` (PDF pp. 4381–4384); S154 / Chapter 56 / `Screening` (PDF pp. 4384–4386).

## Scope

Implement Cross Validation; External Cross Validation; Screening. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Cross Validation / External Cross Validation / Screening, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 56.6: Elastic Net and External Cross Validation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
