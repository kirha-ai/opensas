# STAT-HPREG-006 — HPREG — PARTITION / SELECTION / Criteria Used in Model Selection

## Source

S154 / Chapter 67 / `PARTITION Statement` (PDF p. 5035); S154 / Chapter 67 / `SELECTION Statement` (PDF pp. 5036–5038); S154 / Chapter 67 / `Criteria Used in Model Selection` (PDF pp. 5038–5040).

## Scope

Implement PARTITION; SELECTION; Criteria Used in Model Selection. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION / SELECTION / Criteria Used in Model Selection, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 67.1: Model Selection with Validation; explicit statements: PARTITION, SELECTION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PARTITION, SELECTION. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
