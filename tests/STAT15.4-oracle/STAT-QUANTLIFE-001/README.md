# STAT-QUANTLIFE-001 — QUANTLIFE — Data input, variable roles, and basic options

## Source

S154 / Chapter 102 / `PROC QUANTLIFE Statement` (PDF pp. 8332–8335); S154 / Chapter 102 / `BY Statement` (PDF pp. 8335–8336); S154 / Chapter 102 / `WEIGHT Statement` (PDF p. 8339).

## Scope

Integrate PROC QUANTLIFE declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; WEIGHT; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / WEIGHT, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
