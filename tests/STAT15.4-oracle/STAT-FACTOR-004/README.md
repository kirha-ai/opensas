# STAT-FACTOR-004 — FACTOR — Number of Factors to Retain

## Source

S154 / Chapter 44 / `Number of Factors to Retain` (PDF pp. 2828–2829).

## Scope

Implement Number of Factors to Retain. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Number of Factors to Retain, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 44.3: Determining the Number of Factors to Retain |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
