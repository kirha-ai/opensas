# STAT-HPLOGISTIC-006 — HPLOGISTIC — PARTITION / SELECTION / Using Validation and Test Data

## Source

S154 / Chapter 61 / `PARTITION Statement` (PDF p. 4762); S154 / Chapter 61 / `SELECTION Statement` (PDF pp. 4763–4764); S154 / Chapter 61 / `Using Validation and Test Data` (PDF pp. 4768–4770).

## Scope

Implement PARTITION; SELECTION; Using Validation and Test Data. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION / SELECTION / Using Validation and Test Data, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 61.4: Partitioning Data; explicit statements: PARTITION, SELECTION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARTITION, SELECTION. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
