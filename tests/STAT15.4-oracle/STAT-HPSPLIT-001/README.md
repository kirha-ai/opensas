# STAT-HPSPLIT-001 — HPSPLIT — Data input, variable roles, and basic options

## Source

S154 / Chapter 68 / `PROC HPSPLIT Statement` (PDF pp. 5079–5088); S154 / Chapter 68 / `ID Statement` (PDF p. 5092); S154 / Chapter 68 / `WEIGHT Statement` (PDF p. 5097); S154 / Chapter 68 / `Handling Missing Values` (PDF pp. 5109–5110).

## Scope

Integrate PROC HPSPLIT declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement ID; WEIGHT; Handling Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For ID / WEIGHT / Handling Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ID, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
