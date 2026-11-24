# STAT-HPQUANTSELECT-001 — HPQUANTSELECT — Data input, variable roles, and basic options

## Source

S154 / Chapter 66 / `PROC HPQUANTSELECT Statement` (PDF pp. 4985–4987); S154 / Chapter 66 / `BY Statement` (PDF p. 4987); S154 / Chapter 66 / `ID Statement` (PDF pp. 4988–4989); S154 / Chapter 66 / `WEIGHT Statement` (PDF p. 4995).

## Scope

Integrate PROC HPQUANTSELECT declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; ID; WEIGHT; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / ID / WEIGHT, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Data input, variable roles, and basic options |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
