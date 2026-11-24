# STAT-HPQUANTSELECT-008 — HPQUANTSELECT — PARTITION / SELECTION

## Source

S154 / Chapter 66 / `PARTITION Statement` (PDF p. 4993); S154 / Chapter 66 / `SELECTION Statement` (PDF pp. 4994–4995).

## Scope

Implement PARTITION; SELECTION. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION / SELECTION, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: PARTITION / SELECTION |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
