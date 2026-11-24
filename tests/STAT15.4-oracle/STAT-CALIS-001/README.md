# STAT-CALIS-001 — CALIS — Data input, variable roles, and basic options

## Source

S154 / Chapter 33 / `PROC CALIS Statement` (PDF pp. 1488–1532); S154 / Chapter 33 / `BY Statement` (PDF p. 1534); S154 / Chapter 33 / `FREQ Statement` (PDF p. 1565); S154 / Chapter 33 / `VAR Statement` (PDF pp. 1654–1657); S154 / Chapter 33 / `WEIGHT Statement` (PDF p. 1662); S154 / Chapter 33 / `Input Data Sets` (PDF pp. 1662–1666); S154 / Chapter 33 / `Missing Values and the Analysis of Missing Patterns` (PDF pp. 1802–1803).

## Scope

Integrate PROC CALIS declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; VAR; WEIGHT; Input Data Sets; Missing Values and the Analysis of Missing Patterns; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / VAR / WEIGHT / Input Data Sets / Missing Values and the Analysis of Missing Patterns, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: FREQ, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: FREQ, WEIGHT. Remaining statement variants: BY, VAR.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
