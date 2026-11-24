# STAT-GAM-007 — GAM — Selection of Smoothing Parameters

## Source

S154 / Chapter 48 / `Selection of Smoothing Parameters` (PDF pp. 3314–3316).

## Scope

Implement Selection of Smoothing Parameters. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Selection of Smoothing Parameters, on small candidate sets that can be exhaustively enumerated, verify selection paths, criterion values, tie-breaking, stopping reasons, and the final model; check for partition leakage when validation/test sets are used.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 48.3: Comparing PROC GAM with PROC LOESS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Added the Experiment B fitting step described in prose but omitted from the printed program; PredGAMb is now produced explicitly.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
