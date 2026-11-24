# STAT-GLMSELECT-008 — GLMSELECT — Stepwise Selection (STEPWISE) / Lasso Selection (LASSO) / Adaptive LASSO Selection

## Source

S154 / Chapter 56 / `Stepwise Selection (STEPWISE)` (PDF pp. 4361–4362); S154 / Chapter 56 / `Lasso Selection (LASSO)` (PDF pp. 4363–4364); S154 / Chapter 56 / `Adaptive LASSO Selection` (PDF p. 4364).

## Scope

Implement Stepwise Selection (STEPWISE); Lasso Selection (LASSO); Adaptive LASSO Selection. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Stepwise Selection (STEPWISE) / Lasso Selection (LASSO) / Adaptive LASSO Selection, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 56.7: LASSO with Screening |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
