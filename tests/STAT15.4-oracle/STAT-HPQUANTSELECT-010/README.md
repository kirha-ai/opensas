# STAT-HPQUANTSELECT-010 — HPQUANTSELECT — CODE

## Source

S154 / Chapter 66 / `CODE Statement` (PDF p. 4988).

## Scope

Implement CODE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For CODE, verify predictions/scores, applicable standard errors or intervals, and identifiers row by row; cover new data, unseen levels, missing values, and repeated scoring against independent formulas or source results.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: CODE |
| [statement_code.sas](statement_code.sas) | captured | 0 | [listing](statement_code.expected.txt) / [log](statement_code.oracle.log) | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

**statement_code:** Bounded synthetic case; explicitly executes the targeted statement.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
