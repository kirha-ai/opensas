# STAT-REG-008 — REG — Model-Selection Methods / Criteria Used in Model-Selection Methods / Limitations in Model-Selection Methods

## Source

S154 / Chapter 105 / `Model-Selection Methods` (PDF pp. 8613–8616); S154 / Chapter 105 / `Criteria Used in Model-Selection Methods` (PDF pp. 8616–8617); S154 / Chapter 105 / `Limitations in Model-Selection Methods` (PDF p. 8617).

## Scope

Implement Model-Selection Methods; Criteria Used in Model-Selection Methods; Limitations in Model-Selection Methods. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Model-Selection Methods / Criteria Used in Model-Selection Methods / Limitations in Model-Selection Methods, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
