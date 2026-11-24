# STAT-QUANTSELECT-007 — QUANTSELECT — PARTITION / Forward Selection (FORWARD) / Stepwise Selection (STEPWISE)

## Source

S154 / Chapter 104 / `PARTITION Statement` (PDF pp. 8490–8491); S154 / Chapter 104 / `Forward Selection (FORWARD)` (PDF p. 8496); S154 / Chapter 104 / `Stepwise Selection (STEPWISE)` (PDF pp. 8496–8497).

## Scope

Implement PARTITION; Forward Selection (FORWARD); Stepwise Selection (STEPWISE). Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION / Forward Selection (FORWARD) / Stepwise Selection (STEPWISE), on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: QUANTSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PARTITION.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
