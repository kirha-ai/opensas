# STAT-ADAPTIVEREG-005 — ADAPTIVEREG — PARTITION

## Source

S154 / Chapter 28 / `PARTITION Statement` (PDF pp. 1072–1073).

## Scope

Implement PARTITION. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Adaptive forward/pruning fitting and explicit prediction output on a bounded synthetic mixture design |

**documented_feature:** Synthetic small input replaces an impractically long printed example replay; advanced algorithm variants still need additional cases.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
