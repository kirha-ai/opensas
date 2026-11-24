# STAT-GLMSELECT-007 — GLMSELECT — MODELAVERAGE / PARTITION / Forward Selection (FORWARD)

## Source

S154 / Chapter 56 / `MODELAVERAGE Statement` (PDF pp. 4348–4352); S154 / Chapter 56 / `PARTITION Statement` (PDF pp. 4354–4355); S154 / Chapter 56 / `Forward Selection (FORWARD)` (PDF pp. 4357–4360).

## Scope

Implement MODELAVERAGE; PARTITION; Forward Selection (FORWARD). Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For MODELAVERAGE / PARTITION / Forward Selection (FORWARD), on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 56.1: Modeling Baseball Salaries Using Performance Statistics; explicit statements: PARTITION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARTITION. Remaining statement variants: MODELAVERAGE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
