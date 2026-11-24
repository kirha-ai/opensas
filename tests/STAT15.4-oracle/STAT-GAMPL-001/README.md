# STAT-GAMPL-001 — GAMPL — Data input, variable roles, and basic options

## Source

S154 / Chapter 49 / `PROC GAMPL Statement` (PDF pp. 3356–3362); S154 / Chapter 49 / `FREQ Statement` (PDF p. 3363); S154 / Chapter 49 / `ID Statement` (PDF p. 3363); S154 / Chapter 49 / `WEIGHT Statement` (PDF p. 3374); S154 / Chapter 49 / `Missing Values` (PDF p. 3374).

## Scope

Integrate PROC GAMPL declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement FREQ; ID; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For FREQ / ID / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: ID |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID. Remaining statement variants: FREQ, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
