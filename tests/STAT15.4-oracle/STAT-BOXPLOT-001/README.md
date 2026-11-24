# STAT-BOXPLOT-001 — BOXPLOT — Data input, variable roles, and basic options

## Source

S154 / Chapter 32 / `PROC BOXPLOT Statement` (PDF pp. 1376–1377); S154 / Chapter 32 / `BY Statement` (PDF pp. 1377–1378); S154 / Chapter 32 / `ID Statement` (PDF p. 1378); S154 / Chapter 32 / `Input Data Sets` (PDF pp. 1411–1414); S154 / Chapter 32 / `Missing Values` (PDF p. 1416).

## Scope

Integrate PROC BOXPLOT declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; ID; Input Data Sets; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / ID / Input Data Sets / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: ID.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
