# STAT-QUANTSELECT-008 — QUANTSELECT — Criteria Used in Model Selection Methods / Using Validation and Test Data

## Source

S154 / Chapter 104 / `Criteria Used in Model Selection Methods` (PDF pp. 8497–8500); S154 / Chapter 104 / `Using Validation and Test Data` (PDF pp. 8501–8504).

## Scope

Implement Criteria Used in Model Selection Methods; Using Validation and Test Data. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Criteria Used in Model Selection Methods / Using Validation and Test Data, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: QUANTSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
