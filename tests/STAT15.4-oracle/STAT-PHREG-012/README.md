# STAT-PHREG-012 — PHREG — ASSESS / Effect Selection Methods

## Source

S154 / Chapter 92 / `ASSESS Statement` (PDF pp. 7333–7334); S154 / Chapter 92 / `Effect Selection Methods` (PDF pp. 7449–7450).

## Scope

Implement ASSESS; Effect Selection Methods. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For ASSESS / Effect Selection Methods, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.2: Best Subset Selection |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ASSESS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
