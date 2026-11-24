# STAT-DISCRIM-005 — DISCRIM — TESTCLASS / TESTFREQ / TESTID

## Source

S154 / Chapter 42 / `TESTCLASS Statement` (PDF p. 2663); S154 / Chapter 42 / `TESTFREQ Statement` (PDF p. 2663); S154 / Chapter 42 / `TESTID Statement` (PDF p. 2663).

## Scope

Implement TESTCLASS; TESTFREQ; TESTID. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For TESTCLASS / TESTFREQ / TESTID, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: DISCRIM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: TESTCLASS, TESTFREQ, TESTID.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
