# STAT-HPSPLIT-008 — HPSPLIT — GROW / PARTITION / PRUNE

## Source

S154 / Chapter 68 / `GROW Statement` (PDF pp. 5090–5092); S154 / Chapter 68 / `PARTITION Statement` (PDF pp. 5093–5095); S154 / Chapter 68 / `PRUNE Statement` (PDF pp. 5095–5096).

## Scope

Implement GROW; PARTITION; PRUNE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For GROW / PARTITION / PRUNE, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 68.5: Assessing Variable Importance; explicit statements: PRUNE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PRUNE. Remaining statement variants: GROW, PARTITION. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored complete Dopant and Usable labels with list input after PDF column-space loss.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
