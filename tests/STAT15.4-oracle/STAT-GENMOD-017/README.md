# STAT-GENMOD-017 — GENMOD — STORE

## Source

S154 / Chapter 51 / `STORE Statement` (PDF p. 3565).

## Scope

Implement STORE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For STORE, reload in a new session and reproduce the relevant predictions/inference; verify model metadata, class levels, and parameter covariance; explicitly diagnose incompatible stores or requested functions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [statement_store.sas](statement_store.sas) | captured | 0 | [listing](statement_store.expected.txt) / [log](statement_store.oracle.log) | Save the fitted item store and inspect it through PROC PLM SHOW ALL. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: STORE.

**statement_store:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
