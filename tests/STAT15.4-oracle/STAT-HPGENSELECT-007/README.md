# STAT-HPGENSELECT-007 — HPGENSELECT — PARTITION / SELECTION / The LASSO Method of Model Selection

## Source

S154 / Chapter 59 / `PARTITION Statement` (PDF pp. 4647–4648); S154 / Chapter 59 / `SELECTION Statement` (PDF pp. 4650–4652); S154 / Chapter 59 / `The LASSO Method of Model Selection` (PDF pp. 4663–4666).

## Scope

Implement PARTITION; SELECTION; The LASSO Method of Model Selection. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PARTITION / SELECTION / The LASSO Method of Model Selection, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 59.4: Model Selection by the LASSO Method; explicit statements: SELECTION |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SELECTION. Remaining statement variants: PARTITION. Reduced the million-row performance illustration to 1,500 rows and 15 candidate covariates for a bounded LASSO fixture.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
